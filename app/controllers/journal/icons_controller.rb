module Journal
  # A journal's icon for its tile on Your journals, loaded into the tile
  # after the page (a lazy Turbo frame), so a slow Dreamwidth never holds the
  # page up. The default icon if we can tell which it is, otherwise the first
  # icon, otherwise none.
  class IconsController < ApplicationController
    CACHE_FOR = 1.hour

    before_action :set_connection

    def show
      @icon_url = Rails.cache.fetch([ "journal-icon", @connection.id ], expires_in: CACHE_FOR, skip_nil: true) do
        find_icon_url
      end
      render layout: false
    end

    private

    def find_icon_url
      url = default_icon_url_from_entries || dreamwidth_client.icons.first&.url
      @connection.record_success!
      url
    rescue Dreamwidth::Client::KeyRejected, Dreamwidth::Client::Forbidden
      @connection.record_failure!
      nil
    rescue Dreamwidth::Client::Error
      nil
    end
  end
end
