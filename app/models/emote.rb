# An emote that can be typed as a code (:spring_heart:) into formatted text
# or picked for a profile. Each emote has:
#
# - name: what admins edit, e.g. "02_spring_heart". Sorts the emote within its
#   group, and can itself be typed (:02_spring_heart:).
# - code: the canonical code that pickers insert and profiles store, e.g.
#   "spring_heart". Derived from the name unless code_overridden is set.
# - aliases: old codes, recorded whenever the code changes, so text written
#   with them keeps rendering.
#
# Names, codes and aliases share one namespace: none may be used twice.
class Emote < ApplicationRecord
  IDENTIFIER_FORMAT = /\A[a-z0-9_]+\z/
  MAX_IDENTIFIER_LENGTH = 64

  # The static webp shown everywhere. 64px covers the largest display size
  # (the 32px picker) at 2x.
  DISPLAY_VARIANT = { resize_to_limit: [ 64, 64 ], format: :webp }.freeze

  belongs_to :emote_group
  has_many :aliases, class_name: "EmoteAlias", dependent: :destroy

  # The original upload is kept as-is; only this static webp is ever shown,
  # so animations show their first frame. SVGs never reach the server: the
  # upload page converts them to PNG in the browser (see EmoteUpload).
  has_one_attached :image do |attachable|
    attachable.variant :display, **DISPLAY_VARIANT, preprocessed: true
  end

  normalizes :name, :code, with: ->(value) { value.strip.downcase }

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  before_validation :derive_code, unless: :code_overridden?
  before_update :record_previous_code_as_alias, if: :will_save_change_to_code?

  validates :name, :code, presence: true, length: { maximum: MAX_IDENTIFIER_LENGTH },
    format: { with: IDENTIFIER_FORMAT, message: "can only contain lowercase letters, numbers and underscores", allow_blank: true }
  validates :image, presence: true
  validate :identifiers_are_unique

  before_destroy :remember_codes_for_profile_cleanup, prepend: true
  after_update_commit :rewrite_profile_codes, if: :saved_change_to_code?
  after_destroy_commit :remove_codes_from_profiles
  after_commit { EmoteRegistry.expire_current }

  # "02 Spring-Heart.webp" → "02_spring_heart". Blank when nothing usable is
  # left, e.g. "♥♥♥.png".
  def self.name_from_filename(filename)
    File.basename(filename.to_s, ".*").downcase
      .gsub(/[\s.-]+/, "_")
      .gsub(/[^a-z0-9_]/, "")
      .squeeze("_")
      .delete_prefix("_").delete_suffix("_")
  end

  # The code suggested for a name: the number prefix that sets the sort order
  # is dropped, unless the number is the emote itself (100, 1st_place).
  #   "02_spring_heart" → "spring_heart", "50cadbury_heart" → "cadbury_heart",
  #   "100" → "100", "1st_place" → "1st_place"
  def self.default_code(name)
    name = name.to_s
    return name if name.match?(/\A\d+\z/)
    return name if name.match?(/\A\d+(st|nd|rd|th)(_|\z)/)
    name.sub(/\A\d+_?/, "").presence || name
  end

  # Sorts names the way people read numbers: "2_x" before "10_y".
  def self.natural_sort_key(name)
    name.scan(/\d+|\D+/).map { |part| part.match?(/\A\d/) ? [ 0, part.to_i ] : [ 1, part ] }
  end

  def self.natural_sort(emotes)
    emotes.sort_by { |emote| [ natural_sort_key(emote.name), emote.name ] }
  end

  def archived?
    archived_at.present?
  end

  # Proxy URLs are stable (unlike the expiring redirect URLs), which matters
  # because rendered chat HTML embeds them, and are served with long-lived
  # cache headers. Replacing an image makes a new blob, so a new URL.
  def display_image_path
    return unless image.attached?
    Rails.application.routes.url_helpers.rails_storage_proxy_path(image.variant(:display), only_path: true)
  end

  # Archived emotes are hidden from pickers but keep rendering wherever
  # they're already used.
  def archive!
    update!(archived_at: Time.current)
  end

  def restore!
    update!(archived_at: nil)
  end

  private

  def derive_code
    self.code = self.class.default_code(name) if name.present?
  end

  # Keeps the old code working in existing text. Renaming back to a code this
  # emote used before reclaims it from its aliases instead.
  def record_previous_code_as_alias
    aliases.where(code: code).delete_all
    aliases.find_or_create_by!(code: code_in_database)
  end

  # Profiles store codes, and reads already resolve old codes through aliases,
  # so this only tidies the stored data.
  def rewrite_profile_codes
    old_code, new_code = saved_change_to_code
    Emotes::RewriteProfileCodesJob.perform_later(old_code, new_code)
  end

  def remember_codes_for_profile_cleanup
    @codes_for_profile_cleanup = [ code_in_database, *aliases.pluck(:code) ]
  end

  def remove_codes_from_profiles
    @codes_for_profile_cleanup.each { |old_code| Emotes::RewriteProfileCodesJob.perform_later(old_code, nil) }
  end

  def identifiers_are_unique
    other_emotes = Emote.where.not(id: id)
    other_aliases = EmoteAlias.includes(:emote).where.not(emote_id: id)

    { name: name, code: code }.each do |attribute, value|
      next if value.blank?

      if (other = other_emotes.where(name: value).or(other_emotes.where(code: value)).first)
        errors.add(attribute, "“#{value}” is already used by #{other.name}")
      elsif (existing_alias = other_aliases.find_by(code: value))
        errors.add(attribute, "“#{value}” is an old code of #{existing_alias.emote.name}")
      end
    end
  end
end
