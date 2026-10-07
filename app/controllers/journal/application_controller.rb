module Journal
  class ApplicationController < ::ApplicationController
    # Tests swap in a fake that never touches the network.
    class_attribute :dreamwidth_client_class, default: Dreamwidth::Client

    helper_method :dreamwidth_connections

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

    def dreamwidth_client(connection = @connection)
      dreamwidth_client_class.new(username: connection.username, api_key: connection.api_key)
    end

    # Journal pages show notices just after their h1, so a screen reader
    # reaches them in reading order rather than before the page's heading.
    def inline_flash?
      true
    end
  end
end
