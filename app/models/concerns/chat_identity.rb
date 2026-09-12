module ChatIdentity
  extend ActiveSupport::Concern

  included do
    validate :mini_profile_name_present_when_not_inherited

    # mini_profile_avatar is the independent chat-specific avatar, gated by
    # mini_profile_avatar_inherited (see ApplicationHelper#chat_avatar_for/
    # #chat_avatar_shape_for) rather than attachment presence — shape and alt
    # text can be overridden on their own, keeping the main avatar's image,
    # so "inherited" is the real source of truth, not "is something
    # attached." It has its own shape and alt text, independent of
    # avatar_shape/avatar_alt_text. Deliberately declared here rather than in
    # HasAvatar — HasAvatar is also included by Chat::Server, which isn't a
    # postable and has no chat identity at all, so this can't live somewhere
    # Server would inherit it too.
    has_one_attached :mini_profile_avatar
    validate :mini_profile_avatar_is_valid
    validates :mini_profile_avatar_shape, inclusion: { in: HasAvatar::AVATAR_SHAPES }
  end

  class_methods do
    # Defines `chat_<field>`, resolving to the main field's value when
    # `mini_profile_<field>_inherited?` is true, or the independent
    # `mini_profile_<field>` override otherwise. Chat views should only ever
    # read through these — never the raw `mini_profile_*` columns directly —
    # so inherit-vs-override is resolved in exactly one place.
    def chat_identity_field(field)
      define_method("chat_#{field}") do
        if public_send("mini_profile_#{field}_inherited?")
          public_send(field)
        else
          public_send("mini_profile_#{field}")
        end
      end
    end
  end

  private

  # Unlike every other chat-identity field, name has no safe "blank" state —
  # a chat message has to be posted under some name — so this is the one
  # validation the inherit/override system needs. It defaults to inherited,
  # so this only fires once an owner explicitly opts into an independent
  # name and leaves it blank.
  def mini_profile_name_present_when_not_inherited
    return if mini_profile_name_inherited?
    errors.add(:mini_profile_name, "can't be blank when not inheriting the main name") if mini_profile_name.blank?
  end

  def mini_profile_avatar_is_valid
    return unless mini_profile_avatar.attached?
    unless mini_profile_avatar.blob.content_type.in?(HasAvatar::AVATAR_CONTENT_TYPES)
      errors.add(:mini_profile_avatar, "must be a JPG/JPEG, PNG, or WebP image")
    end
    if mini_profile_avatar.blob.byte_size > HasAvatar::AVATAR_MAX_SIZE
      errors.add(:mini_profile_avatar, "must be 2 MB or less")
    end
    width, height = ImageDimensions.for(mini_profile_avatar)
    if width && (width > HasAvatar::AVATAR_MAX_DIMENSION || height > HasAvatar::AVATAR_MAX_DIMENSION)
      errors.add(:mini_profile_avatar, "must be #{HasAvatar::AVATAR_MAX_DIMENSION}×#{HasAvatar::AVATAR_MAX_DIMENSION} pixels or smaller")
    end
  end
end
