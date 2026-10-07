module Journal
  class EntriesController < ApplicationController
    PER_PAGE = 20

    before_action :set_connection

    # Fetched live every time: there's no local copy of anyone's entries.
    #
    # This GET records whether Dreamwidth accepted the key. That's safe only
    # because journal links never prefetch (Turbo would otherwise ask
    # Dreamwidth on hover), and it only ever records what Dreamwidth said.
    def index
      @offset = [ params[:offset].to_i, 0 ].max
      # One more than a page, to know whether there's an older page at all.
      entries = dreamwidth_client.entries(count: PER_PAGE + 1, offset: @offset, security: ("private" if Journal::PRIVATE_ONLY))
      @has_older = entries.size > PER_PAGE
      @entries = entries.first(PER_PAGE)
      @connection.record_success!
    rescue Dreamwidth::Client::KeyRejected, Dreamwidth::Client::Forbidden
      @connection.record_failure!
      @problem = :key_rejected
    rescue Dreamwidth::Client::NotFound
      @problem = :journal_gone
    rescue Dreamwidth::Client::Error
      @problem = :unavailable
    end
  end
end
