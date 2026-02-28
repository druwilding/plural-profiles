class Our::ProfilesController < ApplicationController
  include OurSidebar
  allow_unauthenticated_access only: :show
  before_action :resume_session, only: :show
  before_action :set_profile, only: %i[ show edit update destroy ]
  before_action :set_groups, only: %i[ new create edit update ]

  def index
    @profiles = Current.user.profiles.order(:name)
  end

  def show
  end

  def new
    @profile = Current.user.profiles.build
  end

  def create
    @profile = Current.user.profiles.build(profile_params)

    if @profile.save
      redirect_to our_profile_path(@profile), notice: "Profile created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @profile.avatar.purge if params[:profile][:remove_avatar] == "1"
    if @profile.update(profile_params)
      redirect_to our_profile_path(@profile), notice: "Profile updated."
    else
      if params.dig(:profile, :avatar).present?
        @profile.avatar.blob&.persisted? ? @profile.avatar.purge_later : @profile.avatar.detach
      end
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @profile.destroy
    redirect_to our_profiles_path, notice: "Profile deleted.", status: :see_other
  end

  private

  def set_profile
    @profile = Current.user&.profiles&.find_by(uuid: params[:id])
    redirect_to profile_path(params[:id]) unless @profile
  end

  def set_groups
    @groups = Current.user.groups.order(:name)
  end

  def profile_params
    params.require(:profile).permit(:name, :pronouns, :description, :avatar, :avatar_alt_text, :created_at, :updated_at, group_ids: []).tap do |p|
      p.delete(:created_at) if p[:created_at].blank?
      p.delete(:updated_at) if p[:updated_at].blank?
    end
  end
end
