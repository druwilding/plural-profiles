class GroupsController < ApplicationController
  allow_unauthenticated_access

  def show
    @group = Group.find_by!(uuid: params[:uuid])
    @direct_profiles = @group.profiles
    @seen_profile_ids = Set.new
    @descendant_tree = @group.descendant_tree(seen_profile_ids: @seen_profile_ids)
  end

  def panel
    @group = Group.find_by!(uuid: params[:uuid])
    @profiles = @group.profiles
    render partial: "groups/group_content", locals: { group: @group, profiles: @profiles }, layout: false
  end
end
