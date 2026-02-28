module HasAvatar
  extend ActiveSupport::Concern

  AVATAR_CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze
  AVATAR_MAX_SIZE = 2.megabytes

  included do
    has_one_attached :avatar
    validate :avatar_content_type_allowed
    validate :avatar_size_allowed
  end

  private

  def avatar_content_type_allowed
    return unless avatar.attached?
    unless avatar.blob.content_type.in?(AVATAR_CONTENT_TYPES)
      errors.add(:avatar, "must be a JPG/JPEG, PNG, or WebP image")
    end
  end

  def avatar_size_allowed
    return unless avatar.attached?
    if avatar.blob.byte_size > AVATAR_MAX_SIZE
      errors.add(:avatar, "must be 2 MB or less")
    end
  end
end
