class GroupsController < ApplicationController
  allow_unauthenticated_access

  def show
    @group = Group.find_by!(uuid: params[:uuid])
    @direct_profiles = @group.profiles.order(:name)
    @descendant_tree = @group.descendant_tree
  end
end
