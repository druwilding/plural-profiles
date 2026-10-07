require "test_helper"

class Dreamwidth::ClientTest < ActiveSupport::TestCase
  # Stands in for the network: records each request and answers with a canned
  # response, or raises, as a test asks.
  class FakeTransport
    attr_reader :requests

    def initialize(status: 200, body: "[]", raises: nil)
      @status = status
      @body = body
      @raises = raises
      @requests = []
    end

    def call(uri, request)
      @requests << [ uri, request ]
      raise @raises if @raises

      response = Net::HTTPResponse::CODE_TO_OBJ.fetch(@status.to_s).new("1.1", @status.to_s, "")
      response.instance_variable_set(:@body, @body)
      response.instance_variable_set(:@read, true)
      response
    end

    def last_uri = requests.last.first
    def last_request = requests.last.last
  end

  def client(transport)
    Dreamwidth::Client.new(username: "example_journal", api_key: "secretKey123", transport: transport)
  end

  ENTRY_JSON = {
    "entry_id" => 29492,
    "url" => "https://example-journal.dreamwidth.org/29492.html",
    "subject" => "API &amp; test",
    "subject_raw" => "API & test",
    "body" => "<b>bold</b> line one<br /><br />line two",
    "body_raw" => "<b>bold</b> line one\n\nline two",
    "datetime" => "2026-10-06 21:34:00",
    "security" => "private",
    "tags" => [ "api test", "second tag" ],
    "icon_keyword" => "(default)"
  }.freeze

  test "only talks to Dreamwidth's API, over HTTPS" do
    transport = FakeTransport.new
    client(transport).entries

    assert_equal "https", transport.last_uri.scheme
    assert_equal "www.dreamwidth.org", transport.last_uri.host
    assert transport.last_uri.path.start_with?("/api/v1/journals/example_journal/")
  end

  test "sends the key only in the Authorization header" do
    transport = FakeTransport.new
    client(transport).entries

    assert_equal "Bearer secretKey123", transport.last_request["Authorization"]
    assert_not_includes transport.last_uri.to_s, "secretKey123"
  end

  test "the username in a path is escaped" do
    transport = FakeTransport.new
    Dreamwidth::Client.new(username: "a/../b", api_key: "k", transport: transport).entries

    assert_equal "/api/v1/journals/a%2F..%2Fb/entries", transport.last_uri.path
  end

  test "entries maps Dreamwidth's JSON to entries, using the raw subject and body" do
    transport = FakeTransport.new(body: [ ENTRY_JSON ].to_json)
    entry = client(transport).entries.first

    assert_equal 29492, entry.id
    assert_equal "API & test", entry.subject
    assert_equal "<b>bold</b> line one\n\nline two", entry.body
    assert_equal "2026-10-06 21:34:00", entry.datetime
    assert_equal "private", entry.security
    assert_equal [ "api test", "second tag" ], entry.tags
    assert_equal "https://example-journal.dreamwidth.org/29492.html", entry.url
  end

  test "an entry without its raw body never falls back to the rendered one" do
    transport = FakeTransport.new(body: [ ENTRY_JSON.except("body_raw") ].to_json)

    assert_nil client(transport).entries.first.body
  end

  test "entries passes count, offset and security as query parameters" do
    transport = FakeTransport.new
    client(transport).entries(count: 10, offset: 20, security: "private")

    assert_equal({ "count" => "10", "offset" => "20", "security" => "private" }, URI.decode_www_form(transport.last_uri.query).to_h)
  end

  test "entries leaves security out unless asked" do
    transport = FakeTransport.new
    client(transport).entries

    assert_not_includes URI.decode_www_form(transport.last_uri.query).to_h.keys, "security"
  end

  test "access_lists maps to ids and names" do
    transport = FakeTransport.new(body: [ { "id" => 1, "name" => "Close friends" } ].to_json)

    assert_equal [ Dreamwidth::AccessList.new(id: 1, name: "Close friends") ], client(transport).access_lists
    assert_equal "/api/v1/journals/example_journal/accesslists", transport.last_uri.path
  end

  test "verify! is true when Dreamwidth shows the journal's access lists" do
    assert client(FakeTransport.new(body: "[]")).verify!
  end

  test "verify! raises Forbidden when the key belongs to another account" do
    assert_raises(Dreamwidth::Client::Forbidden) do
      client(FakeTransport.new(status: 403, body: "")).verify!
    end
  end

  {
    400 => Dreamwidth::Client::Invalid,
    401 => Dreamwidth::Client::KeyRejected,
    403 => Dreamwidth::Client::Forbidden,
    404 => Dreamwidth::Client::NotFound,
    429 => Dreamwidth::Client::Unavailable,
    500 => Dreamwidth::Client::Unavailable,
    504 => Dreamwidth::Client::Unavailable
  }.each do |status, error|
    test "a #{status} raises #{error.name.demodulize}" do
      assert_raises(error) { client(FakeTransport.new(status: status, body: "")).entries }
    end
  end

  test "Dreamwidth's own error message is passed through" do
    body = { "success" => 0, "error" => "Bad format for request body." }.to_json
    error = assert_raises(Dreamwidth::Client::Invalid) do
      client(FakeTransport.new(status: 400, body: body)).entries
    end

    assert_equal "Bad format for request body.", error.message
  end

  test "a 200 that isn't JSON counts as Dreamwidth being unavailable" do
    assert_raises(Dreamwidth::Client::Unavailable) do
      client(FakeTransport.new(body: "<html>Gateway Timeout</html>")).entries
    end
  end

  [ Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError ].each do |network_error|
    test "#{network_error.name} becomes Unavailable" do
      assert_raises(Dreamwidth::Client::Unavailable) do
        client(FakeTransport.new(raises: network_error.new)).entries
      end
    end
  end

  test "the real transport uses short timeouts" do
    assert_equal 5, Dreamwidth::Client::OPEN_TIMEOUT
    assert_equal 15, Dreamwidth::Client::READ_TIMEOUT
  end
end
