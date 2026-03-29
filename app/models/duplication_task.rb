class DuplicationTask < ApplicationRecord
  belongs_to :user
  belongs_to :group

  STATUSES = %w[pending in_progress completed failed].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: %w[pending in_progress]) }

  def completed? = status == "completed"
  def failed? = status == "failed"
  def in_progress? = status == "in_progress"
  def pending? = status == "pending"
  def finished? = completed? || failed?

  def progress_text
    "Copied #{copied_avatars} of #{total_avatars} avatars"
  end
end
