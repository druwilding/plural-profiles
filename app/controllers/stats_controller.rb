class StatsController < ApplicationController
  allow_unauthenticated_access

  def index
    @user_count = User.count
    @profile_count = Profile.count
    @group_count = Group.count
  end
end
