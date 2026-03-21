class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def create
    login_param = params[:login].to_s.strip
    password = params[:password].to_s

    user = if login_param.include?("@")
      User.authenticate_by(email_address: login_param, password: password)
    else
      found = User.where("lower(username) = ?", login_param.downcase).first
      if found
        User.authenticate_by(email_address: found.email_address, password: password)
      else
        User.authenticate_by(email_address: "nobody@invalid", password: password)
        nil
      end
    end

    if user && !user.deactivated?
      start_new_session_for user
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
