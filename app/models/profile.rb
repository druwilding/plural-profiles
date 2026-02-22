class Profile < ApplicationRecord
  belongs_to :user
  has_many :group_profiles, dependent: :destroy
  has_many :groups, through: :group_profiles

  has_one_attached :avatar

  before_create :generate_uuid

  validates :name, presence: true
  validates :uuid, uniqueness: true
  validate :avatar_content_type_allowed

  def to_param
    uuid
  end

  private

  def avatar_content_type_allowed
    return unless avatar.attached?
    unless avatar.blob.content_type.in?(%w[image/png image/jpeg image/gif image/webp])
      errors.add(:avatar, "must be a PNG, JPEG, GIF, or WebP image")
    end
  end

  def generate_uuid
    self.uuid = SecureRandom.uuid
  end
end
