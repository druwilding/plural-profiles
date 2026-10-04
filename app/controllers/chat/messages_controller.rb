module Chat
  class MessagesController < ApplicationController
    before_action :require_membership!
    before_action :set_channel

    layout false, only: :index

    rate_limit to: 60, within: 1.minute, only: :create,
      with: -> { redirect_to chat_server_channel_path(@server, @channel), alert: "You're sending messages too fast — try again in a moment." }

    # Lazily loaded (via a turbo-frame with loading="lazy") as the reader scrolls
    # up through history — see app/views/chat/messages/index.html.haml for the
    # chained-frame pagination this renders.
    def index
      cursor = Chat::Message.new(id: params[:before_id], created_at: Time.iso8601(params[:before_created_at]))
      @messages = Chat::Message.latest_page(@channel.messages.before_cursor(cursor))
      @has_more_messages = @messages.any? && @channel.messages.before_cursor(@messages.first).exists?
    end

    def create
      @message = @channel.messages.build(message_params.merge(user: Current.user))
      if @message.save
        respond_to do |format|
          # Answers without reloading the page: a reload replaces the message
          # box, which closes a phone's keyboard and opens it again. A Turbo
          # Stream answer is how the composer knows the message was saved
          # (composer_controller.js), since a turned-away send redirects like
          # one that worked. It names the message, so the composer can wait
          # for it to appear before handing the box back.
          #
          # The message itself comes only from Chat::Message's broadcast, as
          # for everyone else. Sent here too, Turbo would move the first copy
          # to the end on the second, after any message that landed between.
          format.turbo_stream do
            response.set_header("X-Chat-Message", helpers.dom_id(@message))
          end
          format.html do
            # Tells the page after the redirect to clear this channel's draft
            flash[:sent_message_in] = @channel.uuid
            redirect_to chat_server_channel_path(@server, @channel)
          end
        end
      else
        @messages = Chat::Message.latest_page(@channel.messages)
        @has_more_messages = @messages.any? && @channel.messages.before_cursor(@messages.first).exists?
        @in_channel_chat = true
        render "chat/channels/show", status: :unprocessable_entity
      end
    end

    private

    def set_channel
      @channel = @server.channels.find_by!(uuid: params[:channel_uuid])
      @channel_theme = @channel.theme
    end

    def message_params
      params.require(:chat_message).permit(:body)
    end
  end
end
