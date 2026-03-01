class InviteCode < ApplicationRecord
  CODE_LENGTH = 8
  MAX_UNUSED_PER_USER = 10
  # Deliberately excludes '7' — consistent with PluralProfilesUuid.
  CODE_ALPHABET = (("A".."Z").to_a + ("0".."9").to_a - [ "7" ]).freeze

  belongs_to :user
  belongs_to :redeemed_by, class_name: "User", optional: true

  validates :code, presence: true, uniqueness: true

  scope :unused, -> { where(redeemed_by_id: nil) }
  scope :used, -> { where.not(redeemed_by_id: nil) }

  before_validation :normalize_code
  before_validation :generate_code, on: :create

  def redeemed?
    redeemed_by_id.present?
  end

  def redeem!(new_user)
    with_lock do
      raise ActiveRecord::RecordInvalid.new(self), "Invite code has already been redeemed" if redeemed?

      update!(redeemed_by: new_user, redeemed_at: Time.current)
    end
  end

  private

  def normalize_code
    self.code = code.upcase if code.present?
  end

  def generate_code
    self.code ||= loop {
      candidate = CODE_LENGTH.times.map { CODE_ALPHABET.sample }.join
      break candidate unless InviteCode.exists?(code: candidate)
    }
  end
end
