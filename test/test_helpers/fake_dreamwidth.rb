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
    def add_journal(username, api_key:, entries: [], access_lists: [], icons: [], tags: [])
      journals[username] = { api_keys: Array(api_key), entries: entries, access_lists: access_lists, icons: icons, tags: tags }
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

  def entry(id)
    record(:entry, id: id)
    found = journal[:entries].find { |entry| entry.id.to_s == id.to_s }
    raise Dreamwidth::Client::NotFound, "No such entry" unless found
    raise Dreamwidth::Client::Forbidden, "Not visible" unless own_journal? || found.security == "public"
    found
  end

  # Keeps the entry, as Dreamwidth would, and returns what Dreamwidth does.
  def create_entry(attrs)
    record(:create_entry, **attrs)
    raise Dreamwidth::Client::Forbidden, "Not your journal" unless own_journal?

    id = (journal[:entries].map(&:id).max || 0) + 1
    url = "https://#{username.tr('_', '-')}.dreamwidth.org/#{id}.html"
    icon = journal[:icons].find { |candidate| candidate.keywords.include?(attrs[:icon]) }
    journal[:entries] << Dreamwidth::Entry.new(
      id: id, url: url, subject: attrs[:subject].to_s, body: attrs[:text],
      datetime: attrs[:datetime] ? "#{attrs[:datetime]}:00" : Time.current.strftime("%Y-%m-%d %H:%M:%S"),
      security: attrs[:security] || "public", tags: Array(attrs[:tags]),
      icon_keyword: attrs[:icon] || "(default)", icon_url: icon&.url
    )
    Dreamwidth::Client::Posted.new(id: id, url: url, message: nil)
  end

  def icons
    record(:icons)
    journal[:icons]
  end

  def tags
    record(:tags)
    journal[:tags]
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

  def dreamwidth_entry(id:, subject: "An entry", datetime: "2026-10-06 21:34:00", security: "private", tags: [],
    icon_keyword: "(default)", icon_url: nil)
    Dreamwidth::Entry.new(
      id: id, url: "https://example.dreamwidth.org/#{id}.html", subject: subject, body: "Body of #{id}",
      datetime: datetime, security: security, tags: tags, icon_keyword: icon_keyword, icon_url: icon_url
    )
  end

  def dreamwidth_icon(id:, keywords:)
    Dreamwidth::Icon.new(id: id, keywords: Array(keywords), url: "https://v2.dreamwidth.org/#{id}/1", comment: "")
  end
end
