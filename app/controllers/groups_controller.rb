class GroupsController < ApplicationController
  allow_unauthenticated_access

  def show
    @group = Group.find_by!(uuid: params[:uuid])
    @group_theme = @group.theme
    @direct_profiles = @group.visible_root_profiles
    @seen_profile_ids = Set.new
    @descendant_tree = @group.descendant_tree(seen_profile_ids: @seen_profile_ids)
  end

  def panel
    @group = Group.find_by!(uuid: params[:uuid])
    @group_theme = @group.theme

    if params[:root].present? && params[:root] != params[:uuid]
      root_group = Group.find_by!(uuid: params[:root])
      path = Array(params[:path]).map(&:to_i)
      @profiles = @group.profiles_visible_at_path(path, root_group_id: root_group.id)
    else
      @profiles = @group.visible_root_profiles
    end

    render partial: "groups/group_content", locals: { group: @group, profiles: @profiles }, layout: false
  end
end
