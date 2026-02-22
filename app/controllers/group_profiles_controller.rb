class GroupProfilesController < ApplicationController
  allow_unauthenticated_access

  def show
    @group = Group.find_by!(uuid: params[:group_uuid])
    @profile = @group.profiles.find_by!(uuid: params[:uuid])
  end

  def panel
    @group = Group.find_by!(uuid: params[:group_uuid])
    @profile = @group.profiles.find_by!(uuid: params[:uuid])
    render partial: "groups/profile_content", locals: { group: @group, profile: @profile }, layout: false
  end
end
