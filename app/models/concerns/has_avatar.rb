module HasAvatar
  extend ActiveSupport::Concern

  AVATAR_CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze
  AVATAR_MAX_SIZE = 2.megabytes
  AVATAR_MAX_DIMENSION = 4000
  AVATAR_SHAPES = %w[circle rounded square].freeze

  included do
    has_one_attached :avatar
    validate :avatar_content_type_allowed
    validate :avatar_size_allowed
    validate :avatar_dimensions_allowed
    validates :avatar_shape, inclusion: { in: AVATAR_SHAPES }
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

  def avatar_dimensions_allowed
    return unless avatar.attached?
    width, height = ImageDimensions.for(avatar)
    return if width.nil?
    if width > AVATAR_MAX_DIMENSION || height > AVATAR_MAX_DIMENSION
      errors.add(:avatar, "must be #{AVATAR_MAX_DIMENSION}×#{AVATAR_MAX_DIMENSION} pixels or smaller")
    end
  end
end
