class StatsController < ApplicationController
  def index
    @user_count = User.where(deactivated_at: nil).count
    @profile_count = Profile.count
    @group_count = Group.count
    @avatar_count = ActiveStorage::Attachment.where(name: "avatar", record_type: [ "Profile", "Group" ]).count
    @invite_code_count = InviteCode.where(redeemed_at: nil).count
    @theme_count = Theme.count
  end
end
