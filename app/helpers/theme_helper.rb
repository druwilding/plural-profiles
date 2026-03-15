module ThemeHelper
  def active_theme_style
    override = authenticated? && Current.user&.override_themes?
    public_theme = @group_theme || @profile_theme

    # Logged-in user with an active theme
    if authenticated? && Current.user&.active_theme
      # Use own theme if: override is on, or there is no public theme to show
      return Current.user.active_theme.to_css_properties if override || !public_theme
    end

    # Public theme (skipped entirely if the user has override on, even without an active theme)
    return public_theme.to_css_properties if public_theme && !override

    # Fallback: site default
    Theme.site_default_theme&.to_css_properties
  end
end
