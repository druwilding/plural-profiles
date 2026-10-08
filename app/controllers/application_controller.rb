class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  around_action :set_time_zone

  private

  def require_admin
    redirect_to root_path, alert: "Only admins can access that page." unless Current.user&.admin?
  end

  # Resolves to, in priority order: the user's explicit account preference,
  # the browser-detected time zone cookie, then UTC.
  def set_time_zone(&block)
    Time.use_zone(resolved_time_zone, &block)
  end

  def resolved_time_zone
    # Some actions (e.g. our/profiles#show) resolve the session in their own
    # before_action, which runs after this around_action in the callback
    # chain — call it here too (idempotent) so Current.user is available.
    resume_session

    [ Current.user&.time_zone, cookies[:browser_time_zone] ].each do |name|
      next if name.blank?
      zone = ActiveSupport::TimeZone[name]
      return zone if zone
    end
    "UTC"
  end
end
