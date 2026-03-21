module ThemeHelper
  def active_theme_style
    override = authenticated? && Current.user&.override_themes?
    public_theme = @group_theme || @profile_theme

    # Logged-in user with an active theme
    if authenticated? && Current.user&.active_theme
      # Use own theme if: override is on, or there is no public theme to show
      return theme_style_string(Current.user.active_theme) if override || !public_theme
    end

    # Public theme (skipped entirely if the user has override on, even without an active theme)
    return theme_style_string(public_theme) if public_theme && !override

    # Fallback: site default
    theme = Theme.site_default_theme
    theme_style_string(theme) if theme
  end

  private

    def theme_style_string(theme)
      return unless theme

      style = theme.to_css_properties
      if theme.background_image.attached?
        url = rails_storage_proxy_url(theme.background_image)
        style += " #{theme.background_css_properties(url)}"
      end
      style
    end
end
