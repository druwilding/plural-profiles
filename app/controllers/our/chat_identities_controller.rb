class Our::ChatIdentitiesController < ApplicationController
  # Deliberately no `include OurSidebar` — this page needs the width the
  # sidebar would otherwise take, for the two-column form + live-preview
  # layout. `application.html.haml` only renders the sidebar grid when
  # @sidebar_trees is set, so simply not including the concern is enough.
  POSTABLE_TYPES = { "Profile" => :profiles, "Group" => :groups }.freeze

  before_action :set_postable

  def edit
  end

  def update
    if params[:chat_identity][:remove_mini_profile_avatar] == "1" || params[:chat_identity][:mini_profile_avatar_inherited] == "true"
      @postable.mini_profile_avatar.purge
    end
    if @postable.update(chat_identity_params)
      redirect_to edit_our_chat_identity_path(@postable.class.name, @postable.uuid), notice: "Chat settings updated."
    else
      if params.dig(:chat_identity, :mini_profile_avatar).present?
        @postable.mini_profile_avatar.blob&.persisted? ? @postable.mini_profile_avatar.purge_later : @postable.mini_profile_avatar.detach
      end
      render :edit, status: :unprocessable_entity
    end
  end

  # Renders the same preview-panel partial the edit page's initial render
  # uses (message-row mockup + the real popover partial), against an
  # unsaved in-memory copy of the postable with the current form's values
  # applied — never persisted, purely for the live preview panel.
  def preview
    @postable.assign_attributes(chat_identity_params)
    render partial: "our/chat_identities/preview_panel", locals: { postable: @postable }, layout: false
  end

  private

  def set_postable
    association = POSTABLE_TYPES.fetch(params[:postable_type]) { raise ActiveRecord::RecordNotFound }
    @postable = Current.user.public_send(association).find_by!(uuid: params[:postable_uuid])
  end

  def chat_identity_params
    permitted = %i[chat_bracket_before chat_bracket_after
                   mini_profile_name mini_profile_name_inherited
                   mini_profile_subtitle mini_profile_subtitle_inherited
                   mini_profile_pronouns mini_profile_pronouns_inherited
                   mini_profile_emotes mini_profile_emotes_inherited
                   mini_profile_tag_line mini_profile_tag_line_inherited
                   mini_profile_description mini_profile_description_inherited
                   mini_profile_avatar mini_profile_avatar_alt_text mini_profile_avatar_shape mini_profile_avatar_inherited
                   mini_profile_link_enabled]
    params.require(:chat_identity).permit(*permitted)
  end
end
