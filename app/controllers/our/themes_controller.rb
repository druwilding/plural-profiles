class Our::ThemesController < ApplicationController
  include OurSidebar
  skip_before_action :set_sidebar_data, only: %i[new create edit update activate deactivate destroy duplicate show]
  before_action :set_theme, only: %i[edit update destroy]
  before_action :set_theme_for_duplicate, only: %i[duplicate]
  before_action :set_theme_for_show, only: %i[show activate set_default]

  def index
    @filter_tags = Array(params[:tags]).reject(&:blank?) & Theme::TAGS.keys
    @active_theme = Current.user.active_theme

    @any_shared_themes = Theme.shared.exists?
    @shared_themes = Theme.shared.order(:name)
    @shared_themes = @shared_themes.where("tags @> ARRAY[?]::varchar[]", @filter_tags) if @filter_tags.any?

    own_scope = Current.user.themes
    own_scope = own_scope.where("tags @> ARRAY[?]::varchar[]", @filter_tags) if @filter_tags.any?
    @our_themes = own_scope.order(:name)
  end

  def show
  end

  def new
    colors = Theme::THEMEABLE_PROPERTIES.transform_values { |v| v[:default] }
    default_source = Current.user.active_theme || Theme.site_default_theme
    colors.merge!(default_source.colors) if default_source
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
    @theme.background_image.purge if params.dig(:theme, :remove_background_image) == "1"
    if @theme.update(theme_params)
      redirect_to our_themes_path, notice: "Theme saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @theme.site_default?
      redirect_to our_themes_path, alert: "Cannot delete the default theme. Remove its default status first.", status: :see_other
      return
    end
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
      colors: @theme.colors,
      tags: @theme.tags,
      credit: @theme.credit,
      credit_url: @theme.credit_url,
      notes: @theme.notes,
      shared: false,
      background_repeat: @theme.background_repeat,
      background_size: @theme.background_size,
      background_position: @theme.background_position,
      background_attachment: @theme.background_attachment
      # background_image intentionally not copied — purging an attachment deletes the underlying blob
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
    redirect_to our_themes_path, notice: "Switched to site default theme."
  end

  def set_default
    unless Current.user.admin?
      redirect_to our_themes_path, alert: "Only admins can set the default theme."
      return
    end
    unless @theme.shared?
      redirect_to our_themes_path, alert: "Only shared themes can be set as the default."
      return
    end
    begin
      if @theme.update(site_default: !@theme.site_default?)
        if @theme.site_default?
          redirect_to our_themes_path, notice: "'#{@theme.name}' is now the default theme."
        else
          redirect_to our_themes_path, notice: "'#{@theme.name}' is no longer the default theme."
        end
      else
        redirect_to our_themes_path, alert: "Could not update default theme: #{@theme.errors.full_messages.to_sentence}"
      end
    rescue ActiveRecord::RecordNotUnique
      redirect_to our_themes_path, alert: "Another theme was just set as the default at the same time. Please try again."
    end
  end

  private

  def set_theme
    @theme = Current.user.themes.find_by(id: params[:id])
    @theme ||= Theme.shared.find(params[:id]) if Current.user.admin?
    raise ActiveRecord::RecordNotFound unless @theme
  end

  def set_theme_for_duplicate
    @theme = Theme.shared.find_by(id: params[:id]) || Current.user.themes.find(params[:id])
  end

  def set_theme_for_show
    @theme = Current.user.themes.find_by(id: params[:id]) || Theme.shared.find(params[:id])
  end

  def theme_params
    permitted = params.require(:theme).permit(
      :name, :credit, :credit_url, :notes, :shared, :site_default,
      :background_image, :background_repeat, :background_size,
      :background_position, :background_attachment,
      tags: [], colors: {}
    )
    # Strip admin-only params if user is not admin
    permitted.delete(:shared) unless Current.user.admin?
    permitted.delete(:site_default) unless Current.user.admin?
    # Ensure only known tag values are stored
    permitted[:tags] = (permitted[:tags] || []).reject(&:blank?).uniq & Theme::TAGS.keys
    # Ensure only known colour keys are stored
    if permitted[:colors].present?
      permitted[:colors] = permitted[:colors].to_h.slice(*Theme::THEMEABLE_PROPERTIES.keys)
    end
    permitted
  end
end
