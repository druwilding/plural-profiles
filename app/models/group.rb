class Group < ApplicationRecord
  belongs_to :user
  has_many :group_profiles, dependent: :destroy
  has_many :profiles, through: :group_profiles

  has_one_attached :avatar

  before_create :generate_uuid

  validates :name, presence: true
  validates :uuid, uniqueness: true

  def to_param
    uuid
  end

  private

  def generate_uuid
    self.uuid = SecureRandom.uuid
  end
end
