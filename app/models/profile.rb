class Profile < ApplicationRecord
  include HasAvatar
  include HasLabels
  include ChatProxyable
  include ChatIdentity

  chat_identity_field :name
  chat_identity_field :subtitle
  chat_identity_field :tag_line
  chat_identity_field :description
  chat_identity_field :pronouns
  chat_identity_field :heart_emojis

  belongs_to :user
  belongs_to :theme, optional: true
  belongs_to :copied_from, class_name: "Profile", optional: true
  has_many :copies, class_name: "Profile", foreign_key: :copied_from_id, dependent: :nullify
  has_many :group_profiles, dependent: :destroy
  has_many :groups, through: :group_profiles

  has_many :chat_messages, as: :postable, class_name: "Chat::Message", dependent: :nullify
  has_many :chat_server_memberships, as: :default_postable, class_name: "Chat::Membership", dependent: :nullify
  has_many :chat_channel_default_postables, as: :postable, class_name: "Chat::ChannelDefaultPostable", dependent: :destroy

  before_create :generate_uuid
  after_save :prune_stale_inclusion_overrides, unless: :previously_new_record?
  after_destroy :prune_stale_inclusion_overrides

  validates :name, presence: true
  validates :uuid, uniqueness: true

  validate :heart_emojis_are_valid
  validate :mini_profile_heart_emojis_are_valid

  def to_param
    uuid
  end

  # Returns copies of this profile that have ALL of the given labels.
  # Follows the full copy lineage chain (copies of copies) using a recursive CTE,
  # so a grandchild copy (A → B → C) is found when searching from A.
  def copies_with_labels(labels)
    sql = <<~SQL.squish
      WITH RECURSIVE copy_tree AS (
        SELECT id FROM profiles WHERE copied_from_id = :root_id AND user_id = :user_id
        UNION
        SELECT p.id FROM profiles p
        INNER JOIN copy_tree ct ON p.copied_from_id = ct.id
        WHERE p.user_id = :user_id
      )
      SELECT id FROM copy_tree
    SQL
    all_copy_ids = Profile.connection.select_values(
      Profile.sanitize_sql([ sql, root_id: id, user_id: user_id ])
    ).map(&:to_i)
    Profile.where(id: all_copy_ids, user_id: user_id).where("labels @> ?", labels.to_json)
  end

  # Normalizes any number-prefixed entries (e.g. a stale form submitted after a
  # renumber) to their bare canonical form, so only genuinely unknown hearts
  # fail validation.
  def heart_emojis=(values)
    super(Array(values).map { |value| value.blank? ? value : (HeartEmoji.resolve(value) || value) })
  end

  # Mirrors heart_emojis= — same number-prefix normalization, applied to the
  # independent chat-identity override rather than the main field.
  def mini_profile_heart_emojis=(values)
    super(Array(values).map { |value| value.blank? ? value : (HeartEmoji.resolve(value) || value) })
  end

  private

  def generate_uuid
    self.uuid = PluralProfilesUuid.generate
  end

  # Unticking a group on the profile form removes the link as soon as
  # group_ids= is assigned (inside update's transaction), so by the time
  # this runs any overrides routed through that link are stale.
  def prune_stale_inclusion_overrides
    InclusionOverride.prune_stale!(user)
  end

  def heart_emojis_are_valid
    validate_emote_codes(:heart_emojis)
  end

  def mini_profile_heart_emojis_are_valid
    validate_emote_codes(:mini_profile_heart_emojis)
  end

  # Every code must be a known emote. Archived emotes can't be newly picked,
  # but one that was already picked may stay, so archiving an emote never
  # stops a profile from saving.
  def validate_emote_codes(attribute)
    codes = public_send(attribute)
    return if codes.blank?

    registry = EmoteRegistry.current
    invalid = codes.reject { |code| registry.resolve(code)&.code == code }
    errors.add(attribute, "contains invalid emotes: #{invalid.join(', ')}") if invalid.any?

    newly_added = codes - Array(attribute_in_database(attribute))
    archived = newly_added.select { |code| registry.resolve(code)&.archived? }
    errors.add(attribute, "contains archived emotes: #{archived.join(', ')}") if archived.any?
  end
end
