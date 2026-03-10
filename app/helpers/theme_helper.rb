module ThemeHelper
  def active_theme_style
    return unless authenticated? && Current.user&.active_theme
    Current.user.active_theme.to_css_properties
  end
end
