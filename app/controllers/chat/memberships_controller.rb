module Chat
  class MembershipsController < ApplicationController
    include Chat::FindsPostable

    before_action :require_membership!

    def edit
      load_postable_options
    end

    def update
      default_postable = find_postable(params[:default_postable_type], params[:default_postable_id])
      if default_postable && current_membership
        current_membership.update!(default_postable: default_postable)
        redirect_to chat_server_path(@server), notice: "Updated your default post as."
      else
        redirect_to chat_server_path(@server), alert: "Couldn't update your default post as."
      end
    end

    private

    def load_postable_options
      @profiles = Current.user.profiles.order_by_name_and_labels.includes(avatar_attachment: :blob)
      @groups = Current.user.groups.order_by_name_and_labels.includes(avatar_attachment: :blob)
    end
  end
end
