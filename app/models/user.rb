class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :profiles, dependent: :destroy
  has_many :groups, dependent: :destroy
  has_many :invite_codes, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :unverified_email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :unverified_email_address, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validate :unverified_email_not_taken, if: -> { unverified_email_address.present? }
  validates :password, length: { minimum: 8 }, if: -> { new_record? || password.present? }

  generates_token_for :password_reset, expires_in: 1.hour do
    password_salt&.last(10)
  end

  generates_token_for :email_change, expires_in: 24.hours do
    unverified_email_address
  end

  def email_verified?
    email_verified_at.present?
  end

  def pending_email_change?
    unverified_email_address.present?
  end

  private

  def unverified_email_not_taken
    if User.where.not(id: id)
            .where("email_address = :email OR unverified_email_address = :email", email: unverified_email_address)
            .exists?
      errors.add(:unverified_email_address, "is already taken")
    end
  end
end
