class InviteCode < ApplicationRecord
  CODE_LENGTH = 8
  MAX_UNUSED_PER_USER = 10

  belongs_to :user
  belongs_to :redeemed_by, class_name: "User", optional: true

  validates :code, presence: true, uniqueness: true

  scope :unused, -> { where(redeemed_by_id: nil) }
  scope :used, -> { where.not(redeemed_by_id: nil) }

  before_validation :generate_code, on: :create

  def redeemed?
    redeemed_by_id.present?
  end

  def redeem!(new_user)
    update!(redeemed_by: new_user, redeemed_at: Time.current)
  end

  private

  def generate_code
    self.code ||= loop {
      candidate = SecureRandom.alphanumeric(CODE_LENGTH).upcase
      break candidate unless InviteCode.exists?(code: candidate)
    }
  end
end
