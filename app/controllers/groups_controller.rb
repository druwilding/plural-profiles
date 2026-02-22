class GroupsController < ApplicationController
  allow_unauthenticated_access

  def show
    @group = Group.find_by!(uuid: params[:uuid])
    @direct_profiles = @group.profiles.order(:name)
    @child_groups = @group.child_groups.includes(:profiles).order(:name)
  end
end
