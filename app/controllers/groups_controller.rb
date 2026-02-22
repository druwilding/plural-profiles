class GroupsController < ApplicationController
  allow_unauthenticated_access

  def show
    @group = Group.find_by!(uuid: params[:uuid])
    @direct_profiles = @group.profiles.order(:name)
    @descendant_tree = @group.descendant_tree
  end

  def panel
    @group = Group.find_by!(uuid: params[:uuid])
    @profiles = @group.profiles.order(:name)
    render partial: "groups/group_content", locals: { group: @group, profiles: @profiles }, layout: false
  end
end
