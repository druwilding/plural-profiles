module Journal
  # Connecting a Dreamwidth journal, and managing that connection: replacing
  # its key, or disconnecting it.
  class ConnectionsController < ApplicationController
    # Every save asks Dreamwidth to check the key. Generous: this only stops a
    # runaway loop, not someone fixing a mistyped key.
    rate_limit to: 10, within: 1.minute, only: %i[create update],
      with: -> { redirect_to journal_root_path, alert: "That's a lot of tries in a minute. Wait a moment, then try again." }

    before_action :set_connection, only: %i[show update destroy]

    def new
      @connection = Current.user.dreamwidth_connections.build
    end

    def create
      @connection = Current.user.dreamwidth_connections.build(params.expect(connection: %i[username api_key]))
      @problem = problem_with_new_connection || problem_with_key

      if @problem.nil? && @connection.update(verified_at: Time.current)
        redirect_to journal_dw_entries_path(@connection), notice: "Connected #{@connection.username}."
      else
        @problem ||= :invalid
        render :new, status: :unprocessable_entity
      end
    end

    def show
    end

    # Replacing the key. There's no editing one: the form never shows it.
    def update
      @connection.api_key = params.expect(connection: [ :api_key ])[:api_key]
      @problem = problem_with_replacement_key || problem_with_key

      if @problem
        # Back to the key that was there, which the page describes.
        @connection.restore_attributes
        render :show, status: :unprocessable_entity
      else
        @connection.update!(verified_at: Time.current, failed_at: nil)
        redirect_to journal_dw_connection_path(@connection), notice: "Saved the new key for #{@connection.username}."
      end
    end

    def destroy
      @connection.destroy!
      redirect_to journal_root_path,
        notice: "Disconnected #{@connection.username}. The key still works on Dreamwidth until you revoke it there."
    end

    private

    # In this order, so each message says the most useful thing: pasting the
    # same journal's key again is "already connected", not "already added".
    def problem_with_new_connection
      others = Current.user.dreamwidth_connections

      if @connection.username.present? && (@existing = others.find_by(username: @connection.username))
        :already_connected
      elsif @connection.api_key_digest && (@existing = others.find_by(api_key_digest: @connection.api_key_digest))
        :key_already_added
      elsif @connection.invalid?
        :invalid
      end
    end

    def problem_with_replacement_key
      others = Current.user.dreamwidth_connections.where.not(id: @connection.id)

      if @connection.api_key.blank?
        :no_key
      elsif (@existing = others.find_by(api_key_digest: @connection.api_key_digest))
        :key_already_added
      end
    end

    # Dreamwidth only shows a journal's access lists to its owner, so this
    # tells a wrong key apart from someone else's key.
    def problem_with_key
      dreamwidth_client(@connection).verify!
      nil
    rescue Dreamwidth::Client::KeyRejected
      :key_rejected
    rescue Dreamwidth::Client::Forbidden
      :wrong_account
    rescue Dreamwidth::Client::NotFound
      :no_such_journal
    rescue Dreamwidth::Client::Error
      :unavailable
    end
  end
end
