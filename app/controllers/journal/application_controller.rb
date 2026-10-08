module Journal
  class ApplicationController < ::ApplicationController
    # Tests swap in a fake that never touches the network.
    class_attribute :dreamwidth_client_class, default: Dreamwidth::Client

    helper_method :dreamwidth_connections, :journal_draft_key

    private

    def dreamwidth_connections
      @dreamwidth_connections ||= Current.user.dreamwidth_connections.order(:username)
    end

    # Always through the person's own connections, so a changed URL can never
    # reach someone else's key: it's a 404, the same as a journal they haven't
    # connected.
    def set_connection
      @connection = Current.user.dreamwidth_connections.find_by!(username: params[:dreamwidth_username])
    end

    # Where the Write page's draft is kept in the browser (journal_drafts.js):
    # one per account, whichever journal it was started in, so someone who
    # starts writing in one journal and switches to another finds it there.
    # Per account, so another account in the same browser never sees it.
    def journal_draft_key
      "#{Current.user.id}:new"
    end

    def dreamwidth_client(connection = @connection)
      dreamwidth_client_class.new(username: connection.username, api_key: connection.api_key)
    end

    # Only private entries are listed until Dreamwidth's fixes are live
    # (docs/plan-journal.md, "Private-only mode").
    def listed_security
      "private" if Journal::PRIVATE_ONLY
    end

    # The icon that stands for a journal, on its tile and its Entries page:
    # the default if we can tell, otherwise the first icon, otherwise none.
    # Cached for an hour, so it costs Dreamwidth nothing most of the time.
    def journal_icon_url(connection = @connection)
      Rails.cache.fetch([ "journal-icon", connection.id ], expires_in: 1.hour, skip_nil: true) do
        url = default_icon_url_from_entries(connection) || dreamwidth_client(connection).icons.first&.url
        connection.record_success!
        url
      end
    rescue Dreamwidth::Client::KeyRejected, Dreamwidth::Client::Forbidden
      connection.record_failure!
      nil
    rescue Dreamwidth::Client::Error
      nil
    end

    # Dreamwidth doesn't yet say which icon is the default
    # (dreamwidth/dreamwidth#3696), but an entry posted with "(default)"
    # reports the icon it used, so the newest one shows the current default.
    def default_icon_url_from_entries(connection = @connection)
      dreamwidth_client(connection).entries(count: 10, security: listed_security)
        .find { |entry| entry.icon_keyword == "(default)" }&.icon_url
    end
  end
end
