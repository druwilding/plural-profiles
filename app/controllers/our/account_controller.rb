class Our::AccountController < ApplicationController
  include OurSidebar

  def show
  end

  def update_password
    if !Current.user.authenticate(params[:current_password])
      redirect_to our_account_path, alert: "Current password is incorrect."
    elsif Current.user.update(password_params)
      redirect_to our_account_path, notice: "Password updated."
    else
      redirect_to our_account_path, alert: Current.user.errors.full_messages.to_sentence
    end
  end

  def update_email
    new_email = params[:unverified_email_address].to_s.strip.downcase

    if new_email == Current.user.email_address
      redirect_to our_account_path, alert: "That's already your current email address."
    elsif Current.user.update(unverified_email_address: params[:unverified_email_address])
      UserMailer.verify_new_email(Current.user).deliver_later
      UserMailer.notify_email_change(Current.user).deliver_later
      redirect_to our_account_path, notice: "Verification email sent to #{new_email}. Please check your inbox."
    else
      redirect_to our_account_path, alert: Current.user.errors.full_messages.to_sentence
    end
  end

  private

  def password_params
    params.permit(:password, :password_confirmation)
  end
end
