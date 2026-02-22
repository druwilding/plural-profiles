module HasAvatar
  extend ActiveSupport::Concern

  AVATAR_CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze

  included do
    has_one_attached :avatar
    validate :avatar_content_type_allowed
  end

  private

  def avatar_content_type_allowed
    return unless avatar.attached?
    unless avatar.blob.content_type.in?(AVATAR_CONTENT_TYPES)
      errors.add(:avatar, "must be a PNG, JPEG, GIF, or WebP image")
    end
  end
end
