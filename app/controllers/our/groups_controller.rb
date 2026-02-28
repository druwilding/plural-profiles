class Our::GroupsController < ApplicationController
  include OurSidebar
  allow_unauthenticated_access only: :show
  before_action :resume_session, only: :show
  before_action :set_group, only: %i[ show edit update destroy manage_profiles add_profile remove_profile manage_groups add_group remove_group update_relationship ]

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
      redirect_to our_group_path(@group), notice: "Group created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @group.avatar.purge if params[:group][:remove_avatar] == "1"
    if @group.update(group_params)
      redirect_to our_group_path(@group), notice: "Group updated."
    else
      if params.dig(:group, :avatar).present?
        @group.avatar.blob&.persisted? ? @group.avatar.purge_later : @group.avatar.detach
      end
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @group.destroy
    redirect_to our_groups_path, notice: "Group deleted.", status: :see_other
  end

  def manage_profiles
    @available_profiles = Current.user.profiles.where.not(id: @group.profile_ids).order(:name)
  end

  def add_profile
    profile = Current.user.profiles.find(params[:profile_id])
    @group.profiles << profile unless @group.profiles.include?(profile)
    redirect_to manage_profiles_our_group_path(@group), notice: "Profile added to group."
  rescue ActiveRecord::RecordNotFound
    redirect_to manage_profiles_our_group_path(@group), alert: "Profile not found."
  end

  def remove_profile
    profile = @group.profiles.find(params[:profile_id])
    @group.profiles.delete(profile)
    redirect_to manage_profiles_our_group_path(@group), notice: "Profile removed from group."
  end

  def manage_groups
    excluded_ids = @group.descendant_group_ids | @group.ancestor_group_ids
    @available_groups = Current.user.groups
      .where.not(id: excluded_ids)
      .order(:name)
    @child_links = @group.child_links.includes(
      child_group: [
        { avatar_attachment: :blob },
        { child_links: :child_group }
      ]
    ).order("groups.name")
  end

  def add_group
    child = Current.user.groups.find(params[:group_id])
    group_group = @group.child_links.build(child_group: child)
    if group_group.save
      redirect_to manage_groups_our_group_path(@group), notice: "Group added."
    else
      redirect_to manage_groups_our_group_path(@group), alert: group_group.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to manage_groups_our_group_path(@group), alert: "Group not found."
  end

  def remove_group
    child = @group.child_groups.find(params[:group_id])
    @group.child_groups.delete(child)
    redirect_to manage_groups_our_group_path(@group), notice: "Group removed."
  rescue ActiveRecord::RecordNotFound
    redirect_to manage_groups_our_group_path(@group), alert: "Group not found."
  end

  def update_relationship
    link = @group.child_links.find_by!(child_group_id: params[:group_id])
    allowed_modes = %w[all selected none]

    if params[:inclusion_mode].present?
      mode = params[:inclusion_mode].to_s
      mode = "none" unless allowed_modes.include?(mode)

      if mode == "selected"
        included = Array(params[:included_subgroup_ids]).map(&:to_i)
        # Only allow immediate sub-groups of the child to be included
        valid_included = included & link.child_group.child_group_ids
      else
        # For 'all' or 'none' we clear the explicit list to keep data consistent
        valid_included = []
      end

      link.update!(inclusion_mode: mode, included_subgroup_ids: valid_included)
    end

    redirect_to manage_groups_our_group_path(@group), notice: "Relationship updated."
  rescue ActiveRecord::RecordNotFound
    redirect_to manage_groups_our_group_path(@group), alert: "Group not found."
  end

  private

  def set_group
    @group = Current.user&.groups&.find_by(uuid: params[:id])
    redirect_to group_path(params[:id]) unless @group
  end

  def group_params
    params.require(:group).permit(:name, :description, :avatar, :avatar_alt_text, :created_at, :updated_at).tap do |p|
      p.delete(:created_at) if p[:created_at].blank?
      p.delete(:updated_at) if p[:updated_at].blank?
    end
  end
end
