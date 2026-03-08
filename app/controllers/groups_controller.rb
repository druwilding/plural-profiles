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

    if params[:root].present? && params[:root] != params[:uuid]
      root_group = Group.find_by!(uuid: params[:root])
      visible_from_root = root_group.all_profiles
      @profiles = @group.profiles.where(id: visible_from_root.select(:id))
    else
      @profiles = @group.profiles
    end

    render partial: "groups/group_content", locals: { group: @group, profiles: @profiles }, layout: false
  end
end
