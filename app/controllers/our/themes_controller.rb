class Our::ThemesController < ApplicationController
  include OurSidebar
  skip_before_action :set_sidebar_data, only: %i[new create edit update activate deactivate destroy duplicate]
  before_action :set_theme, only: %i[edit update destroy activate duplicate]

  def index
    @themes = Current.user.themes.order(:name)
  end

  def new
    colors = Theme::THEMEABLE_PROPERTIES.transform_values { |v| v[:default] }
    if params[:theme].present? && params[:theme][:colors].present?
      imported = params[:theme][:colors].to_unsafe_h.transform_keys(&:to_s).slice(*Theme::THEMEABLE_PROPERTIES.keys)
      colors.merge!(imported)
    end
    @theme = Current.user.themes.build(
      name: "New theme",
      colors: colors
    )
  end

  def create
    @theme = Current.user.themes.build(theme_params)
    if @theme.save
      redirect_to our_themes_path, notice: "Theme created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @theme.update(theme_params)
      redirect_to our_themes_path, notice: "Theme saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if Current.user.active_theme_id == @theme.id
      Current.user.update!(active_theme_id: nil)
    end
    @theme.destroy
    redirect_to our_themes_path, notice: "Theme deleted.", status: :see_other
  end

  def duplicate
    suffix = " (copy)"
    base_name = @theme.name.truncate(255 - suffix.length, omission: "")
    copy = Current.user.themes.build(
      name: "#{base_name}#{suffix}",
      colors: @theme.colors
    )
    if copy.save
      redirect_to edit_our_theme_path(copy), notice: "Theme duplicated. You're now editing the copy."
    else
      redirect_to our_themes_path, alert: "Could not duplicate theme: #{copy.errors.full_messages.to_sentence}"
    end
  end

  def activate
    Current.user.update!(active_theme: @theme)
    redirect_to our_themes_path, notice: "Theme '#{@theme.name}' is now active."
  end

  def deactivate
    Current.user.update!(active_theme: nil)
    redirect_to our_themes_path, notice: "Switched back to default theme."
  end

  private

  def set_theme
    @theme = Current.user.themes.find(params[:id])
  end

  def theme_params
    permitted = params.require(:theme).permit(:name, colors: {})
    # Ensure only known colour keys are stored
    if permitted[:colors].present?
      permitted[:colors] = permitted[:colors].to_h.slice(*Theme::THEMEABLE_PROPERTIES.keys)
    end
    permitted
  end
end
