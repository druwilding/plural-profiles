# An old code of an emote, recorded when the emote's code changes so that
# text and profiles written with the old code keep resolving.
class EmoteAlias < ApplicationRecord
  belongs_to :emote, touch: true

  validates :code, presence: true, uniqueness: true, format: { with: Emote::IDENTIFIER_FORMAT }

  after_commit { EmoteRegistry.expire_current }
end
