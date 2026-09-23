# A named section of emotes ("Hearts", "Other"), shown as a heading in the
# pickers. A NULL owner means the group is site-wide; the polymorphic owner is
# reserved for future server (Chat::Server) and personal (User) emote groups.
class EmoteGroup < ApplicationRecord
  belongs_to :owner, polymorphic: true, optional: true
  has_many :emotes, -> { order(:name) }, dependent: :restrict_with_error

  scope :site_wide, -> { where(owner_type: nil, owner_id: nil) }
  scope :ordered, -> { order(:position, :name) }

  validates :name, presence: true, uniqueness: { scope: [ :owner_type, :owner_id ], case_sensitive: false }
  validate :plain_text_is_a_short_symbol

  after_commit { EmoteRegistry.expire_current }

  private

  # The stand-in used where emotes can't be images (page titles, confirm
  # dialogs), e.g. "♥". Counted in grapheme clusters so a multi-codepoint
  # emoji still counts as one.
  def plain_text_is_a_short_symbol
    length = plain_text.to_s.strip.grapheme_clusters.length
    if length.zero?
      errors.add(:plain_text, "can't be blank")
    elsif length > 4
      errors.add(:plain_text, "must be at most 4 characters")
    end
  end
end
