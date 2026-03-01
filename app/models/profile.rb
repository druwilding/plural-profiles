class Profile < ApplicationRecord
  include HasAvatar

  belongs_to :user
  has_many :group_profiles, dependent: :destroy
  has_many :groups, through: :group_profiles

  before_create :generate_uuid

  validates :name, presence: true
  validates :uuid, uniqueness: true
  validates :created_at, comparison: { less_than_or_equal_to: -> { Time.current + 1.minute }, message: "can't be in the future" }, allow_nil: true, if: :created_at_changed?

  def to_param
    uuid
  end

  private

  def generate_uuid
    self.uuid = PluralProfilesUuid.generate
  end
end
