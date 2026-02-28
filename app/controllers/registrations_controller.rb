class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  before_action :check_signups_enabled

  def new
    @user = User.new
  end

  def create
    @invite_code = InviteCode.unused.find_by(code: params[:invite_code].to_s.strip.upcase)

    if @invite_code.nil?
      @user = User.new(registration_params)
      @user.valid? # populate other errors too
      @user.errors.add(:base, "Invite code invalid or already used")
      render :new, status: :unprocessable_entity
      return
    end

    @user = User.new(registration_params)
    success = false

    ApplicationRecord.transaction do
      # Lock the invite row so concurrent registrations serialise here.
      @invite_code.lock!

      # Re-check inside the lock: another request may have redeemed this code
      # between the find_by above and acquiring the lock.
      if @invite_code.redeemed?
        @user.errors.add(:base, "Invite code invalid or already used")
        raise ActiveRecord::Rollback
      end

      if @user.save
        @invite_code.redeem!(@user)
        success = true
      else
        raise ActiveRecord::Rollback
      end
    end

    if success
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
