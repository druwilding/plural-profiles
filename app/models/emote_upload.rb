# Uploading emotes, one file or many.
#
# process checks each file and imports every one it can straight away, named
# from its filename. Files only wait for a decision when their name or code is
# already in use (a clash: replace that emote's image, add under a new name,
# or skip), or when no name can be made from the filename. Those files are
# stored as unattached blobs so the decision page can show them, and resolve
# applies the decisions.
#
# Only PNG and WebP are accepted, judged by the file's bytes rather than its
# name. SVGs are converted to PNG in the admin's browser before uploading
# (emote_upload_controller.js): libvips' SVG loader isn't hardened against
# malicious files, and Active Storage disables it.
#
# Blobs left behind by abandoned decisions are purged by
# PurgeOrphanEmoteUploadsJob; they're tagged with BLOB_METADATA_KEY.
class EmoteUpload
  MAX_FILES = 50
  MAX_FILE_SIZE = 2.megabytes
  CONTENT_TYPES = %w[image/png image/webp].freeze
  ACTIONS = %w[create replace skip].freeze
  BLOB_METADATA_KEY = "emote_upload".freeze

  # One uploaded file.
  #
  # status is:
  # - "new": can be imported as is
  # - "clash": its name or code is already an emote's name, code or old code
  #   (clash is that emote)
  # - "duplicate": an earlier file in this upload has the same name or code
  # - "unnamed": no name could be made from the filename
  # - "invalid": rejected; error says why, and there's no blob
  class Row
    include ActiveModel::AttributeAssignment

    attr_accessor :blob, :filename, :name, :group_id, :action, :status, :clash, :error, :emote
    attr_writer :errors_list

    def initialize(**attributes)
      assign_attributes(attributes)
    end

    def signed_id
      blob&.signed_id
    end

    def code
      Emote.default_code(name)
    end

    def invalid?
      status == "invalid"
    end

    def errors_list
      @errors_list ||= []
    end
  end

  # group_ids: the groups that gained an emote or had one's image replaced.
  Result = Data.define(:added, :replaced, :skipped, :group_ids) do
    def self.none
      new(added: 0, replaced: 0, skipped: 0, group_ids: [])
    end
  end

  # What process did: result (what was imported), pending (rows waiting for a
  # decision), rejected (invalid files), and truncated (more than MAX_FILES
  # were sent, and the rest were ignored).
  Outcome = Data.define(:result, :pending, :rejected, :truncated)

  def self.process(files, group_id:)
    files = Array(files).select { |file| file.respond_to?(:original_filename) }
    rows = classify(files.first(MAX_FILES).map { |file| stage_file(file, group_id) })
    rejected = rows.select(&:invalid?)

    clean = rows.select { |row| row.status == "new" }
    result = import(clean)
    pending = rows.reject { |row| row.invalid? || (result && clean.include?(row)) }

    # Imported files may now clash with a later file of the same name, which
    # was a duplicate; checking again turns it into a clash with that emote.
    pending.each { |row| row.action = nil }
    classify(pending, just_added: result ? clean.map { |row| row.emote.id } : [])

    Outcome.new(result: result || Result.none, pending: pending, rejected: rejected, truncated: files.size > MAX_FILES)
  end

  # Applies the decisions submitted from the decision page. Returns
  # [result, rows]; result is nil when any row failed, in which case nothing
  # was saved and the failed rows have errors_list set.
  def self.resolve(row_params)
    rows = rows_from_params(row_params)
    [ import(rows), rows ]
  end

  # Rebuilds rows from the decision form's params. Rows whose blob can't be
  # found, or wasn't stored by an emote upload (a tampered signed id), are
  # dropped.
  def self.rows_from_params(row_params)
    list = row_params.respond_to?(:values) ? row_params.values : Array(row_params)
    rows = list.filter_map do |params|
      blob = ActiveStorage::Blob.find_signed(params[:signed_id].to_s)
      next unless blob&.metadata&.dig(BLOB_METADATA_KEY)

      Row.new(
        blob: blob,
        filename: blob.filename.to_s,
        name: params[:name].to_s.strip.downcase,
        group_id: site_group_id(params[:group_id]),
        action: ACTIONS.include?(params[:action]) ? params[:action] : "skip",
        clash: params[:replace_id].presence && site_emotes.find_by(id: params[:replace_id])
      )
    end
    rows
  end

  # Sets each row's status and, for a clash, the emote it clashes with, and a
  # default action if it has none: import new files, replace the image of a
  # clash with an existing emote, but skip a clash with an emote this same
  # upload just added (just_added), since that's two files with one name.
  def self.classify(rows, just_added: [])
    taken = taken_identifiers
    seen = {}

    rows.each do |row|
      next if row.invalid?

      identifiers = [ row.name, row.code ].compact_blank.uniq
      clash_id = identifiers.filter_map { |identifier| taken[identifier]&.fetch(:id) }.first
      row.clash = clash_id && site_emotes.find(clash_id)
      row.status =
        if row.name.blank? then "unnamed"
        elsif row.clash then "clash"
        elsif identifiers.any? { |identifier| seen[identifier] } then "duplicate"
        else "new"
        end
      identifiers.each { |identifier| seen[identifier] = true }

      row.action ||=
        if row.status != "clash" then "create"
        elsif just_added.include?(row.clash.id) then "skip"
        else "replace"
        end
    end
    rows
  end

  # Every site-wide emote name, code and old code, with the emote it belongs
  # to, so the decision page can flag clashes as names are edited.
  def self.taken_identifiers
    site_emotes.includes(:aliases, image_attachment: :blob).each_with_object({}) do |emote, taken|
      details = { id: emote.id, name: emote.name, src: emote.display_image_path }
      [ emote.name, emote.code, *emote.aliases.map(&:code) ].each { |identifier| taken[identifier] = details }
    end
  end

  # Applies rows in one transaction: create a new emote, replace the clashing
  # emote's image, or skip. Returns a Result, or nil if any row failed, in
  # which case nothing is saved and each failed row has errors_list set.
  # Skipped files are purged.
  def self.import(rows)
    return Result.none if rows.empty?

    result = nil
    ActiveRecord::Base.transaction do
      rows.each { |row| apply(row) }
      raise ActiveRecord::Rollback if rows.any? { |row| row.errors_list.any? }

      counts = rows.map(&:action).tally
      group_ids = rows.filter_map { |row| row.emote&.emote_group_id || (row.clash&.emote_group_id if row.action == "replace") }.uniq
      result = Result.new(added: counts.fetch("create", 0), replaced: counts.fetch("replace", 0), skipped: counts.fetch("skip", 0), group_ids: group_ids)
    end

    rows.select { |row| row.action == "skip" }.each { |row| row.blob.purge_later } if result
    result
  end

  def self.apply(row)
    case row.action
    when "create"
      row.emote = Emote.new(emote_group_id: row.group_id, name: row.name, image: row.blob)
      row.errors_list = row.emote.errors.full_messages unless row.emote.save
    when "replace"
      if row.clash.nil?
        row.errors_list = [ "There's no existing emote with this name to replace" ]
      elsif !row.clash.image.attach(row.blob)
        row.errors_list = row.clash.errors.full_messages
      end
    end
  end

  def self.stage_file(file, group_id)
    filename = file.original_filename.to_s
    row = Row.new(filename: filename, name: Emote.name_from_filename(filename), group_id: site_group_id(group_id))

    content_type = Marcel::MimeType.for(file.tempfile, name: filename)
    error =
      if file.size > MAX_FILE_SIZE
        "is larger than #{MAX_FILE_SIZE / 1.megabyte} MB"
      elsif content_type == "image/svg+xml" || filename.downcase.end_with?(".svg")
        "is an SVG that wasn't converted to PNG before uploading. The upload page converts SVGs in your browser, so check that JavaScript is turned on"
      elsif !CONTENT_TYPES.include?(content_type)
        "isn't a PNG or WebP image"
      end
    return invalid(row, error) if error

    file.tempfile.rewind
    blob = ActiveStorage::Blob.create_and_upload!(io: file.tempfile, filename: filename, content_type: content_type,
      metadata: { BLOB_METADATA_KEY => true }, identify: false)

    begin
      blob.variant(Emote::DISPLAY_VARIANT).processed
    rescue StandardError => e
      Rails.logger.info("Emote upload #{filename.inspect} couldn't be processed: #{e.class}: #{e.message}")
      blob.purge
      return invalid(row, "couldn't be read as an image")
    end

    row.blob = blob
    row
  end

  def self.invalid(row, error)
    row.status = "invalid"
    row.error = error
    row
  end

  def self.site_emotes
    Emote.joins(:emote_group).merge(EmoteGroup.site_wide)
  end

  def self.site_group_id(id)
    groups = EmoteGroup.site_wide.ordered.pluck(:id)
    groups.include?(id.to_i) ? id.to_i : groups.first
  end

  private_class_method :apply, :stage_file, :invalid, :site_emotes, :site_group_id
end
