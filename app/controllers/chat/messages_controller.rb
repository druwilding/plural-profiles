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
        # Tells the page after the redirect to clear this channel's draft (see
        # composer_controller.js). A turned-away send redirects too, so the
        # browser can't tell from the response alone.
        flash[:sent_message_in] = @channel.uuid
        redirect_to chat_server_channel_path(@server, @channel)
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
