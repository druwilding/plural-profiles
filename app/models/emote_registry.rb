# Every emote, loaded from the database once and kept in plain Ruby lookups so
# rendering formatted text (every chat message, every profile field) never
# queries emotes directly.
#
# The built registry is shared by all threads in the process and rebuilt only
# when the database's emote version changes. The version is checked once per
# request (it's memoised in Current), with a single cheap query, so edits made
# in one process reach every other process on its next request. The cache store
# is per-process (memory_store), so a Rails.cache counter wouldn't do that.
class EmoteRegistry
  Entry = Data.define(:id, :name, :code, :label, :src, :group_id, :archived) do
    alias_method :archived?, :archived
  end
  Group = Data.define(:id, :name, :plain_text, :position)

  # A number before the name, e.g. the "11_" in "11_aqua_heart" or the "50" in
  # "50cadbury_heart": old Discord-numbered pastes. Only stripped when a letter
  # follows, so "100" is never reduced to "00".
  LEGACY_NUMBER_PREFIX = /\A\d+_?(?=[a-z])/

  VERSION_SQL = <<~SQL.squish.freeze
    SELECT concat_ws('/',
      (SELECT count(*) FROM emote_groups), (SELECT max(updated_at) FROM emote_groups),
      (SELECT count(*) FROM emotes), (SELECT max(updated_at) FROM emotes),
      (SELECT count(*) FROM emote_aliases), (SELECT max(updated_at) FROM emote_aliases))
  SQL

  @mutex = Mutex.new
  @built = nil

  class << self
    # The site-wide registry. Future scoped emotes would add
    # EmoteRegistry.for(server:, user:), merging site entries with the scope's.
    def current
      Current.emote_registry ||= begin
        version = ActiveRecord::Base.connection.select_value(VERSION_SQL)
        @mutex.synchronize do
          @built = build(version) unless @built&.version == version
          @built
        end
      end
    end

    # Called after any emote change is committed, so the rest of this request
    # (e.g. re-rendering after an admin edit) sees it.
    def expire_current
      Current.emote_registry = nil
    end

    private

    def build(version)
      groups = EmoteGroup.site_wide.ordered.map do |group|
        Group.new(id: group.id, name: group.name, plain_text: group.plain_text, position: group.position)
      end
      group_order = groups.each_with_index.to_h { |group, index| [ group.id, index ] }

      emotes = Emote.joins(:emote_group).merge(EmoteGroup.site_wide)
        .includes(:aliases, image_attachment: :blob).to_a
      emotes.sort_by! { |emote| [ group_order.fetch(emote.emote_group_id, groups.size), natural_sort_key(emote.name), emote.name ] }

      new(version: version, groups: groups, emotes: emotes)
    end

    # "2_x" before "10_y": digit runs compare as numbers.
    def natural_sort_key(name)
      name.scan(/\d+|\D+/).map { |part| part.match?(/\A\d/) ? [ 0, part.to_i ] : [ 1, part ] }
    end
  end

  attr_reader :version, :groups, :entries

  def initialize(version:, groups:, emotes:)
    @version = version
    @groups = groups.freeze
    @entries = emotes.map { |emote| entry_for(emote) }.freeze
    @by_name = @entries.index_by(&:name)
    @by_code = @entries.index_by(&:code)
    @by_alias = emotes.each_with_object({}) do |emote, lookup|
      emote.aliases.each { |emote_alias| lookup[emote_alias.code] = @by_code[emote.code] }
    end
    @groups_by_id = @groups.index_by(&:id)
  end

  # Entries that can be offered in pickers and autocomplete. Archived emotes
  # still resolve (so existing text keeps rendering) but aren't offered.
  def pickable
    @pickable ||= entries.reject(&:archived?)
  end

  # Finds the emote for a typed code: its name (:02_spring_heart:, :100:), its
  # code (:spring_heart:), an old code (alias), or, for old Discord-numbered
  # pastes, the code or alias after the number (:11_aqua_heart:). Case and
  # hyphens-for-underscores don't matter.
  def resolve(raw)
    key = raw.to_s.downcase.tr("-", "_")
    return if key.empty?

    @by_name[key] || @by_code[key] || @by_alias[key] || begin
      bare = key.sub(LEGACY_NUMBER_PREFIX, "")
      @by_code[bare] || @by_alias[bare] if bare != key
    end
  end

  def group(id)
    @groups_by_id[id]
  end

  private

  def entry_for(emote)
    Entry.new(
      id: emote.id,
      name: emote.name,
      code: emote.code,
      label: emote.code.tr("_", " "),
      src: image_src(emote),
      group_id: emote.emote_group_id,
      archived: emote.archived?
    )
  end

  # Proxy URLs are stable (unlike the expiring redirect URLs), which matters
  # because rendered chat HTML embeds them, and are served with long-lived
  # cache headers. Replacing an image makes a new blob, so a new URL.
  def image_src(emote)
    return unless emote.image.attached?
    Rails.application.routes.url_helpers.rails_storage_proxy_path(emote.image.variant(:display), only_path: true)
  end
end
