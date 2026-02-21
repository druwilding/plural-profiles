class My::GroupsController < ApplicationController
  before_action :set_group, only: %i[ show edit update destroy manage_profiles add_profile remove_profile ]

  def index
    @groups = Current.user.groups.order(:name)
  end

  def show
  end

  def new
    @group = Current.user.groups.build
  end

  def create
    @group = Current.user.groups.build(group_params)

    if @group.save
      redirect_to my_group_path(@group), notice: "Group created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @group.update(group_params)
      redirect_to my_group_path(@group), notice: "Group updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @group.destroy
    redirect_to my_groups_path, notice: "Group deleted.", status: :see_other
  end

  def manage_profiles
    @available_profiles = Current.user.profiles.where.not(id: @group.profile_ids).order(:name)
  end

  def add_profile
    profile = Current.user.profiles.find(params[:profile_id])
    @group.profiles << profile unless @group.profiles.include?(profile)
    redirect_to manage_profiles_my_group_path(@group), notice: "Profile added to group."
  rescue ActiveRecord::RecordNotFound
    redirect_to manage_profiles_my_group_path(@group), alert: "Profile not found."
  end

  def remove_profile
    profile = @group.profiles.find(params[:profile_id])
    @group.profiles.delete(profile)
    redirect_to manage_profiles_my_group_path(@group), notice: "Profile removed from group."
  end

  private

  def set_group
    @group = Current.user.groups.find_by!(uuid: params[:id])
  end

  def group_params
    params.require(:group).permit(:name, :description)
  end
end
