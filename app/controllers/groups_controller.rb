class GroupsController < ApplicationController
  allow_unauthenticated_access

  def show
    @group = Group.find_by!(uuid: params[:uuid])
    @profiles = @group.all_profiles.order(:name)
    @child_groups = @group.child_groups.order(:name)
  end
end
