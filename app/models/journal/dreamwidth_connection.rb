module Journal
  # One person's link to a Dreamwidth journal: its username and the API key
  # they pasted in. A person can connect any number of journals, and two
  # people can connect the same one (a shared household journal), so
  # uniqueness is only ever within one person's connections.
  class DreamwidthConnection < JournalRecord
    self.table_name = "journal_dreamwidth_connections"

    # Dreamwidth's own limits (its API rejects anything else in a path).
    USERNAME_FORMAT = /\A[a-z0-9_]{3,25}\z/

    belongs_to :user

    encrypts :api_key

    # Dreamwidth treats "Foo-Bar" and "foo_bar" as the same account and stores
    # the lowercase, underscore form. Normalising here also applies to
    # where/find_by, so a lookup from a URL finds the same row whichever form
    # it was typed in.
    normalizes :username, with: ->(username) { username.strip.downcase.tr("-", "_") }

    validates :username, presence: true,
      format: { with: USERNAME_FORMAT, message: "must be 3 to 25 letters, numbers, underscores or hyphens", allow_blank: true },
      uniqueness: { scope: :user_id, message: "is already connected" }
    validates :api_key, presence: true
    validates :api_key_digest, uniqueness: { scope: :user_id, message: "is already connected" }, allow_nil: true

    # Encrypted values can't be searched, so "you've already added this key"
    # needs something that can. An HMAC rather than a bare SHA-256, so a copy
    # of the database alone can't confirm a key someone already holds.
    def self.digest_api_key(key)
      OpenSSL::HMAC.hexdigest("SHA256", digest_secret, key)
    end

    def self.digest_secret
      Rails.application.key_generator.generate_key("journal/dreamwidth_connection/api_key_digest", 32)
    end

    # Pasted keys often bring a stray space or newline with them, at the ends
    # or (from wrapping) in the middle. No Dreamwidth key has either, so they
    # go wherever they are.
    def api_key=(key)
      key = key.to_s.gsub(/[[:space:][:cntrl:]]/, "").presence
      super(key)
      self.api_key_digest = key && self.class.digest_api_key(key)
    end

    # Journal URLs name the journal, not our row id, so a page always says
    # which journal it's for.
    def to_param
      username
    end

    # The most a page ever shows of a key.
    def api_key_last_four
      api_key&.last(4)
    end

    def failed?
      failed_at.present?
    end

    # Dreamwidth stopped accepting the key, most likely because it was revoked.
    # Kept until a call succeeds again or the key is replaced.
    def record_failure!
      update!(failed_at: Time.current) unless failed?
    end

    # Dreamwidth accepted the key: clears a failure, and moves verified_at
    # ("Last checked with Dreamwidth" on Manage) on. Not more than once a
    # minute, so browsing entries doesn't write on every page.
    def record_success!
      changes = {}
      changes[:failed_at] = nil if failed?
      changes[:verified_at] = Time.current if verified_at.nil? || verified_at < 1.minute.ago
      update!(changes) if changes.any?
    end
  end
end
