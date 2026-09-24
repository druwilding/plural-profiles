# A named section of emotes ("Hearts", "Other"), shown as a heading in the
# pickers. A NULL owner means the group is site-wide; the polymorphic owner is
# reserved for future server (Chat::Server) and personal (User) emote groups.
class EmoteGroup < ApplicationRecord
  belongs_to :owner, polymorphic: true, optional: true
  has_many :emotes, -> { order(:name) }, dependent: :restrict_with_error

  scope :site_wide, -> { where(owner_type: nil, owner_id: nil) }
  scope :ordered, -> { order(:position, :name) }

  validates :name, presence: true, uniqueness: { scope: [ :owner_type, :owner_id ], case_sensitive: false }

  after_commit { EmoteRegistry.expire_current }
end
