module ThemeHelper
  def active_theme_style
    theme = if authenticated? && Current.user&.active_theme
              Current.user.active_theme
    else
              Theme.site_default_theme
    end
    theme&.to_css_properties
  end
end
