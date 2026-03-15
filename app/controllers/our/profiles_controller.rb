class Our::ProfilesController < ApplicationController
  include OurSidebar
  allow_unauthenticated_access only: :show
  before_action :resume_session, only: :show
  before_action :set_profile, only: %i[ show edit update destroy regenerate_uuid ]
  before_action :set_groups, only: %i[ new create edit update ]
  before_action :validate_theme_choice, only: %i[create update]

  def index
    @profiles = Current.user.profiles.order(:name)
    if params[:label].present?
      @profiles = @profiles.where("labels @> ?", [ params[:label] ].to_json)
    end
    @all_labels = Current.user.profiles
      .joins("CROSS JOIN LATERAL jsonb_array_elements_text(labels) AS label_val")
      .distinct
      .order("label_val")
      .pluck("label_val")
  end

  def show
  end

  def new
    @profile = Current.user.profiles.build
    load_theme_options
  end

  def create
    @profile = Current.user.profiles.build(profile_params)

    if @profile.save
      redirect_to our_profile_path(@profile), notice: "Profile created."
    else
      load_theme_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_theme_options
  end

  def update
    @profile.avatar.purge if params[:profile][:remove_avatar] == "1"
    if @profile.update(profile_params)
      redirect_to our_profile_path(@profile), notice: "Profile updated."
    else
      if params.dig(:profile, :avatar).present?
        @profile.avatar.blob&.persisted? ? @profile.avatar.purge_later : @profile.avatar.detach
      end
      load_theme_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @profile.destroy
    redirect_to our_profiles_path, notice: "Profile deleted.", status: :see_other
  end

  def regenerate_uuid
    @profile.update!(uuid: PluralProfilesUuid.generate)
    redirect_to our_profile_path(@profile), notice: "Share URL regenerated."
  end

  private

  def set_profile
    @profile = Current.user&.profiles&.find_by(uuid: params[:id])
    redirect_to profile_path(params[:id]) unless @profile
  end

  def set_groups
    @groups = Current.user.groups.order(:name)
  end

  def load_theme_options
    @personal_themes = Current.user.themes.personal.order(:name)
    @shared_themes = Theme.shared.order(:name)
  end

  def validate_theme_choice
    theme_id = params.dig(:profile, :theme_id)
    return if theme_id.blank?

    allowed_ids = Current.user.theme_ids + Theme.shared.pluck(:id)
    unless allowed_ids.include?(theme_id.to_i)
      @profile ||= Current.user.profiles.build
      @profile.errors.add(:theme, "is not available")
      load_theme_options
      template = action_name == "create" ? :new : :edit
      render template, status: :unprocessable_entity
    end
  end

  def profile_params
    params.require(:profile).permit(:name, :pronouns, :description, :avatar, :avatar_alt_text, :created_at, :labels_text, :theme_id, group_ids: [], heart_emojis: []).tap do |p|
      p[:heart_emojis] = p[:heart_emojis].reject(&:blank?) if p.key?(:heart_emojis)
      if p[:created_at].blank? ||
          !p[:created_at].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\z/) ||
          (@profile&.created_at && p[:created_at] == @profile.created_at.utc.strftime("%Y-%m-%dT%H:%M"))
        p.delete(:created_at)
      end
    end
  end
end
