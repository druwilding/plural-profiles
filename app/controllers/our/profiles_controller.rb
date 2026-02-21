class Our::ProfilesController < ApplicationController
  before_action :set_profile, only: %i[ show edit update destroy ]

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
    if @profile.update(profile_params)
      redirect_to our_profile_path(@profile), notice: "Profile updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @profile.destroy
    redirect_to our_profiles_path, notice: "Profile deleted.", status: :see_other
  end

  private

  def set_profile
    @profile = Current.user.profiles.find_by!(uuid: params[:id])
  end

  def profile_params
    params.require(:profile).permit(:name, :pronouns, :description, :avatar)
  end
end
