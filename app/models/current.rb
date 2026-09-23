class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :emote_registry
  delegate :user, to: :session, allow_nil: true
end
