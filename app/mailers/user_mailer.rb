class UserMailer < ApplicationMailer
  def email_verification(user)
    @user = user
    @verification_url = email_verification_url(token: user.signed_id(purpose: :email_verification, expires_in: 24.hours))
    mail to: @user.email_address, subject: "Verify your email address"
  end

  def verify_new_email(user)
    @user = user
    @new_email = user.unverified_email_address
    @verification_url = email_verification_url(token: user.generate_token_for(:email_change))
    mail to: @new_email, subject: "Verify your new email address"
  end

  def notify_email_change(user)
    @user = user
    @new_email = user.unverified_email_address
    mail to: @user.email_address, subject: "Your email address is being changed"
  end
end
