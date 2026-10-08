module Journal
  class EntriesController < ApplicationController
    include CreatedAtPartsParsing

    PER_PAGE = 20

    # Generous: only there to stop a runaway loop, not to limit writing.
    rate_limit to: 30, within: 1.minute, only: :create,
      with: -> { redirect_to journal_dw_entries_path(params[:dreamwidth_username]), alert: "That's a lot of posts in a minute. Wait a moment, then try again." }

    before_action :set_connection

    # Fetched live every time: there's no local copy of anyone's entries.
    #
    # The GETs here record whether Dreamwidth accepted the key. That's safe
    # only because journal links never prefetch (Turbo would otherwise ask
    # Dreamwidth on hover), and it only ever records what Dreamwidth said.
    def index
      @offset = [ params[:offset].to_i, 0 ].max
      # One more than a page, to know whether there's an older page at all.
      entries = dreamwidth_client.entries(count: PER_PAGE + 1, offset: @offset, security: listed_security)
      @has_older = entries.size > PER_PAGE
      @entries = entries.first(PER_PAGE)
      @connection.record_success!
    rescue Dreamwidth::Client::Error => error
      @problem = problem_for(error)
    end

    def new
      now = Time.zone.now.strftime("%Y-%m-%dT%H:%M")
      @form = EntryForm.new(datetime: now, datetime_original: now)
      load_icons
    end

    def create
      @form = EntryForm.new(entry_params)
      return render_form if @form.invalid?

      posted = dreamwidth_client.create_entry(@form.to_api)
      @connection.record_success!

      if posted.id
        redirect_to journal_dw_entry_path(@connection, posted.id), notice: "Your entry has been posted."
      else
        redirect_to journal_dw_entries_path(@connection), notice: posted.message.presence || "Your entry has been sent to Dreamwidth."
      end
    rescue Dreamwidth::Client::Invalid => error
      @problem = :invalid
      @problem_message = error.message
      render_form
    rescue Dreamwidth::Client::Error => error
      @problem = problem_for(error)
      render_form
    end

    # Where Write lands after posting: what Dreamwidth actually saved, read
    # back rather than echoed from the form, so a surprise shows here.
    def show
      @entry = dreamwidth_client.entry(params[:id])
      @connection.record_success!
    rescue Dreamwidth::Client::NotFound
      @problem = :entry_gone
    rescue Dreamwidth::Client::Error => error
      @problem = problem_for(error)
    end

    private

    def listed_security
      "private" if Journal::PRIVATE_ONLY
    end

    def entry_params
      permitted = params.expect(entry: [ :subject, :body, :tags, :icon, :security, :datetime_original,
                                         datetime_parts: %i[month day year hour minute] ])
      permitted.merge(datetime: parse_created_at_parts(permitted.delete(:datetime_parts)))
    end

    # Never a redirect: the person's writing has to come back with the page.
    def render_form
      load_icons
      render :new, status: :unprocessable_entity
    end

    # The icons to choose from, and the default icon's image if we can tell
    # which it is. Dreamwidth doesn't yet say which icon is the default
    # (dreamwidth/dreamwidth#3696), but an entry posted with "(default)"
    # reports the icon it used, so the newest one shows the current default.
    def load_icons
      @icons = dreamwidth_client.icons.flat_map do |icon|
        icon.keywords.map { |keyword| [ keyword, icon.url ] }
      end.sort_by { |keyword, _url| keyword.downcase }
      @default_icon_url = dreamwidth_client.entries(count: 10, security: listed_security)
        .find { |entry| entry.icon_keyword == "(default)" }&.icon_url
    rescue Dreamwidth::Client::Error
      @icons ||= []
    end

    def problem_for(error)
      case error
      when Dreamwidth::Client::KeyRejected, Dreamwidth::Client::Forbidden
        @connection.record_failure!
        :key_rejected
      when Dreamwidth::Client::NotFound then :journal_gone
      when Dreamwidth::Client::TimedOut then :timed_out
      else :unavailable
      end
    end
  end
end
