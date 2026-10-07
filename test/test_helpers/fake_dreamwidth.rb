# A pretend Dreamwidth, so journal tests never touch the network. Holds
# journals, their keys and their entries in memory, and answers the way
# Dreamwidth does: a key is only accepted for its own journal's access lists,
# and anyone's key can list a journal's public entries.
class FakeDreamwidthClient
  class << self
    attr_accessor :journals, :failure, :calls

    def reset!
      self.journals = {}
      self.failure = nil
      self.calls = []
    end

    # api_key can be a list: a Dreamwidth account can have several keys.
    def add_journal(username, api_key:, entries: [], access_lists: [])
      journals[username] = { api_keys: Array(api_key), entries: entries, access_lists: access_lists }
    end

    # Every call fails with this error until reset (Unavailable, KeyRejected…).
    def fail_with(error_class)
      self.failure = error_class
    end
  end

  reset!

  attr_reader :username

  def initialize(username:, api_key:)
    @username = username
    @api_key = api_key
  end

  def verify!
    access_lists
    true
  end

  def access_lists
    record(:access_lists)
    raise Dreamwidth::Client::Forbidden, "Not your journal" unless own_journal?
    journal[:access_lists]
  end

  def entries(count: 25, offset: 0, security: nil)
    record(:entries, count: count, offset: offset, security: security)
    list = journal[:entries].sort_by(&:datetime).reverse
    list = list.select { |entry| entry.security == "public" } unless own_journal?
    list = list.select { |entry| entry.security == security } if security
    list.drop(offset).first(count)
  end

  private

  def record(method, **args)
    self.class.calls << [ method, username, args ]
    raise self.class.failure if self.class.failure
    raise Dreamwidth::Client::NotFound, "No such journal" unless journal
    raise Dreamwidth::Client::KeyRejected, "Bad key" unless known_key?
  end

  def journal
    self.class.journals[username]
  end

  def own_journal?
    journal[:api_keys].include?(@api_key)
  end

  def known_key?
    self.class.journals.values.any? { |journal| journal[:api_keys].include?(@api_key) }
  end
end

module FakeDreamwidthHelper
  def self.included(base)
    base.setup do
      FakeDreamwidthClient.reset!
      @real_dreamwidth_client_class = Journal::ApplicationController.dreamwidth_client_class
      Journal::ApplicationController.dreamwidth_client_class = FakeDreamwidthClient
    end

    base.teardown do
      Journal::ApplicationController.dreamwidth_client_class = @real_dreamwidth_client_class
    end
  end

  def dreamwidth_entry(id:, subject: "An entry", datetime: "2026-10-06 21:34:00", security: "private", tags: [])
    Dreamwidth::Entry.new(
      id: id, url: "https://example.dreamwidth.org/#{id}.html", subject: subject, body: "Body of #{id}",
      datetime: datetime, security: security, tags: tags, icon_keyword: "(default)"
    )
  end
end
