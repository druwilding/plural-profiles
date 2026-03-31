class User < ApplicationRecord
  include SidebarTree

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :profiles, dependent: :destroy
  has_many :groups, dependent: :destroy
  has_many :invite_codes, dependent: :destroy
  has_many :themes, dependent: :destroy
  belongs_to :active_theme, class_name: "Theme", optional: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :unverified_email_address, with: ->(e) { e.strip.downcase }
  normalizes :username, with: ->(u) { value = u.strip.downcase; value.blank? ? nil : value }, apply_to_nil: false

  USERNAME_FORMAT = /\A[a-z0-9](?:[a-z0-9]|[_-](?=[a-z0-9]))*[a-z0-9]?\z/
  RESERVED_USERNAMES = %w[
    admin api help support system health status dashboard settings
    null undefined root www mail ftp
    account accounts login logout signup
    register password reset verify
    profile profiles group groups stats
    about our contact terms privacy security
    theme themes docs documentation
  ].uniq.freeze

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :unverified_email_address, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validate :unverified_email_not_taken, if: -> { unverified_email_address.present? }
  validates :password, length: { minimum: 8 }, if: -> { new_record? || password.present? }
  validates :username,
    length: { minimum: 2, maximum: 30 },
    format: { with: USERNAME_FORMAT, message: "can only contain lowercase letters, numbers, underscores, and hyphens (no leading/trailing/consecutive special characters)" },
    uniqueness: { case_sensitive: false },
    allow_blank: true
  validate :username_not_reserved

  generates_token_for :password_reset, expires_in: 1.hour do
    password_salt&.last(10)
  end

  generates_token_for :email_change, expires_in: 24.hours do
    unverified_email_address
  end

  def email_verified?
    email_verified_at.present?
  end

  def deactivated?
    deactivated_at.present?
  end

  def deactivate!
    self.class.transaction do
      update!(deactivated_at: Time.current)
      sessions.delete_all
    end
  end

  def pending_email_change?
    unverified_email_address.present?
  end

  def self.human_attribute_name(attr, options = {})
    attr.to_sym == :username ? "Account name" : super
  end

  private

  def username_not_reserved
    return if username.blank?
    if RESERVED_USERNAMES.include?(username)
      errors.add(:username, "is reserved and cannot be used")
    end
  end

  def unverified_email_not_taken
    if User.where.not(id: id)
            .where("email_address = :email OR unverified_email_address = :email", email: unverified_email_address)
            .exists?
      errors.add(:unverified_email_address, "is already taken")
    end
  end
end
