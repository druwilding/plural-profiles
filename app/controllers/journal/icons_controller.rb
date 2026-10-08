module Journal
  # A journal's icon for its tile on Your journals (see journal_icon_url),
  # loaded into the tile after the page (a lazy Turbo frame), so a slow
  # Dreamwidth never holds the page up.
  class IconsController < ApplicationController
    before_action :set_connection

    def show
      @icon_url = journal_icon_url
      render layout: false
    end
  end
end
