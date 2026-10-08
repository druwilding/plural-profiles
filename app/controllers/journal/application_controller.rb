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
    # per account and connection, so another account never sees it.
    def journal_draft_key(connection = @connection)
      "#{Current.user.id}:#{connection.id}:new"
    end

    def dreamwidth_client(connection = @connection)
      dreamwidth_client_class.new(username: connection.username, api_key: connection.api_key)
    end

    # Only private entries are listed until Dreamwidth's fixes are live
    # (docs/plan-journal.md, "Private-only mode").
    def listed_security
      "private" if Journal::PRIVATE_ONLY
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
