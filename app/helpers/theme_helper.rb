module ThemeHelper
  # background_image: false omits the theme's background image, keeping only the
  # colour custom properties. The chat layout passes it: chat is a fixed-height
  # app-like surface where a tiling or fixed-position image reads as noise
  # behind the server list and settings pages, and never shows behind the
  # messages themselves anyway (.chat-main paints an opaque background over
  # it). Chat uses the flat --chat-page-bg instead.
  def active_theme_style(background_image: true)
    override = authenticated? && Current.user&.override_themes?
    public_theme = @channel_theme || @server_theme || @group_theme || @profile_theme

    # Logged-in user with an active theme
    if authenticated? && Current.user&.active_theme
      # Use own theme if: override is on, or there is no public theme to show
      return theme_style_string(Current.user.active_theme, background_image:) if override || !public_theme
    end

    # Public theme (skipped entirely if the user has override on, even without an active theme)
    return theme_style_string(public_theme, background_image:) if public_theme && !override

    # Fallback: site default
    theme = Theme.site_default_theme
    theme_style_string(theme, background_image:) if theme
  end

  private

    def theme_style_string(theme, background_image: true)
      return unless theme

      style = theme.to_css_properties
      if background_image && theme.background_image.attached?
        url = rails_storage_proxy_url(theme.background_image)
        style += " #{theme.background_css_properties(url)}"
      end
      style
    end
end
