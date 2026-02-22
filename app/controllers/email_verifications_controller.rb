class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access

  def show
    if params[:token].present?
      try_email_change(params[:token]) || try_email_verification(params[:token])
    else
      redirect_to new_session_path, alert: "Invalid or expired verification link."
    end
  end

  private

  def try_email_change(token)
    user = User.find_signed(token, purpose: :email_change)
    return false unless user
    return false unless user.unverified_email_address.present?

    user.update!(email_address: user.unverified_email_address, unverified_email_address: nil, email_verified_at: Time.current)
    user.sessions.destroy_all
    redirect_to new_session_path, notice: "Email address updated and verified! Please sign in with your new email."
    true
  end

  def try_email_verification(token)
    user = User.find_signed!(token, purpose: :email_verification)
    user.update!(email_verified_at: Time.current)
    redirect_to new_session_path, notice: "Email verified! You can now sign in."
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to new_session_path, alert: "Invalid or expired verification link."
  end
end
