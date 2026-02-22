class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  before_action :check_signups_enabled

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)

    if @user.save
      UserMailer.email_verification(@user).deliver_later
      redirect_to new_session_path, notice: "Account created! Please check your email to verify your address."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def check_signups_enabled
    return if ENV.fetch("SIGNUPS_ENABLED", "true") == "true"

    render :closed, status: :ok
  end

  def registration_params
    params.require(:user).permit(:email_address, :password, :password_confirmation)
  end
end
