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
      visibility = root_group.cached_profile_visibility
      if visibility[:all_group_ids].include?(@group.id)
        @profiles = @group.profiles
      else
        selected_ids = visibility[:selected_profile_ids]
        matching = @group.profile_ids & selected_ids.to_a
        @profiles = matching.any? ? @group.profiles.where(id: matching) : Profile.none
      end
    else
      @profiles = @group.profiles
    end

    render partial: "groups/group_content", locals: { group: @group, profiles: @profiles }, layout: false
  end
end
