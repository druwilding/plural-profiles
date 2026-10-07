require "net/http"

module Dreamwidth
  # Talks to Dreamwidth's REST API (https://www.dreamwidth.org/api/v1/spec)
  # with one journal's API key. Knows nothing about controllers or our models,
  # so the importer can reuse it as is.
  #
  # Every failure is raised as one of a few errors the controllers can phrase
  # kindly, never as a raw HTTP or socket error.
  class Client
    # Always this host. Nothing from a request ever changes it.
    BASE_URL = "https://www.dreamwidth.org/api/v1/".freeze

    # A slow Dreamwidth mustn't hold a Puma thread for long: the app runs on
    # few threads.
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15

    class Error < StandardError; end
    # 401: the key is wrong or has been revoked.
    class KeyRejected < Error; end
    # 403: the key works but belongs to someone else (or can't do this).
    class Forbidden < Error; end
    # 404: no such journal or entry.
    class NotFound < Error; end
    # 400: Dreamwidth's message about what was wrong with the request.
    class Invalid < Error; end
    # Timeouts, connection failures, 429 and 5xx: worth trying again later.
    class Unavailable < Error; end

    # The real network call. Tests pass their own transport instead, which
    # answers with canned responses.
    class NetHttpTransport
      def call(uri, request)
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
          http.request(request)
        end
      end
    end

    NETWORK_ERRORS = [
      Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError,
      OpenSSL::SSL::SSLError, EOFError, IOError
    ].freeze

    attr_reader :username

    def initialize(username:, api_key:, transport: NetHttpTransport.new)
      @username = username
      @api_key = api_key
      @transport = transport
    end

    # Confirms the key belongs to this journal. Dreamwidth only shows a
    # journal's access lists to its owner (403 to anyone else), and reading
    # them changes nothing, so it's a safe ownership check. The entries
    # endpoints wouldn't do: they happily list someone else's public entries.
    def verify!
      access_lists
      true
    end

    def access_lists
      get(journal_path("accesslists")).map { |list| AccessList.from_api(list) }
    end

    # Newest first. security is "public", "private" or "access" to only list
    # those.
    def entries(count: 25, offset: 0, security: nil)
      query = { count: count, offset: offset, security: security }.compact
      get(journal_path("entries"), query).map { |entry| Entry.from_api(entry) }
    end

    private

    def journal_path(*segments)
      [ "journals", username, *segments ].map { |segment| ERB::Util.url_encode(segment.to_s) }.join("/")
    end

    def get(path, query = {})
      uri = URI.join(BASE_URL, path)
      uri.query = URI.encode_www_form(query) if query.any?
      request = Net::HTTP::Get.new(uri)
      perform(uri, request)
    end

    def perform(uri, request)
      # The key only ever travels in this header: never in a URL, where it
      # could end up in a log.
      request["Authorization"] = "Bearer #{@api_key}"
      request["Accept"] = "application/json"

      response = begin
        @transport.call(uri, request)
      rescue *NETWORK_ERRORS => error
        raise Unavailable, "Couldn't reach Dreamwidth (#{error.class})"
      end

      handle(response)
    end

    def handle(response)
      case response.code.to_i
      when 200..299 then parse(response.body)
      when 400 then raise Invalid, error_message(response)
      when 401 then raise KeyRejected, error_message(response)
      when 403 then raise Forbidden, error_message(response)
      when 404 then raise NotFound, error_message(response)
      else raise Unavailable, "Dreamwidth answered #{response.code}"
      end
    end

    # A 2xx with something other than JSON (an HTML error page from a proxy,
    # say) is Dreamwidth having trouble, not a reason to crash.
    def parse(body)
      JSON.parse(body.to_s)
    rescue JSON::ParserError
      raise Unavailable, "Dreamwidth sent something that wasn't JSON"
    end

    def error_message(response)
      JSON.parse(response.body.to_s)["error"].presence || "Dreamwidth answered #{response.code}"
    rescue JSON::ParserError, TypeError
      "Dreamwidth answered #{response.code}"
    end
  end
end
