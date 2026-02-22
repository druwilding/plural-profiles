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

  private

  def password_params
    params.permit(:password, :password_confirmation)
  end
end
