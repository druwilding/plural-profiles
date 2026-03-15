module ThemeHelper
  def active_theme_style
    # Logged-in user with an active theme
    if authenticated? && Current.user&.active_theme
      # Accessibility override: always use their own theme, even on group pages
      if Current.user.override_group_themes? || !@group_theme
        return Current.user.active_theme.to_css_properties
      end
    end

    # Group theme set by controller (unauthenticated visitor, or user without override)
    return @group_theme.to_css_properties if @group_theme

    # Fallback: site default
    Theme.site_default_theme&.to_css_properties
  end
end
