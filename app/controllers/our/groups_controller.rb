class Our::GroupsController < ApplicationController
  include OurSidebar
  allow_unauthenticated_access only: :show
  before_action :resume_session, only: :show
  before_action :set_group, only: %i[ show edit update destroy manage_profiles add_profile remove_profile add_group remove_group regenerate_uuid manage_groups toggle_visibility ]
  before_action :validate_theme_choice, only: %i[create update]

  def index
    @groups = Current.user.groups.order(:name)
    if params[:label].present?
      @groups = @groups.where("labels @> ?", [ params[:label] ].to_json)
    end
    @all_labels = Current.user.groups
      .joins("CROSS JOIN LATERAL jsonb_array_elements_text(labels) AS label_val")
      .distinct
      .order("label_val")
      .pluck("label_val")
  end

  def show
  end

  def new
    @group = Current.user.groups.build
    load_theme_options
  end

  def create
    @group = Current.user.groups.build(group_params)

    if @group.save
      redirect_to our_group_path(@group), notice: "Group created."
    else
      load_theme_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_theme_options
  end

  def update
    @group.avatar.purge if params[:group][:remove_avatar] == "1"
    if @group.update(group_params)
      redirect_to our_group_path(@group), notice: "Group updated."
    else
      if params.dig(:group, :avatar).present?
        @group.avatar.blob&.persisted? ? @group.avatar.purge_later : @group.avatar.detach
      end
      load_theme_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @group.destroy
    redirect_to our_groups_path, notice: "Group deleted.", status: :see_other
  end

  def regenerate_uuid
    @group.update!(uuid: PluralProfilesUuid.generate)
    redirect_to our_group_path(@group), notice: "Share URL regenerated."
  end

  def manage_profiles
    @available_profiles = Current.user.profiles.where.not(id: @group.profile_ids).order(:name)
  end

  def add_profile
    profile = Current.user.profiles.find(params[:profile_id])
    @group.profiles << profile unless @group.profiles.include?(profile)
    redirect_to manage_profiles_our_group_path(@group), notice: "Profile added to group."
  rescue ActiveRecord::RecordNotFound
    redirect_to manage_profiles_our_group_path(@group), alert: "Profile not found."
  end

  def remove_profile
    profile = @group.profiles.find(params[:profile_id])
    @group.profiles.delete(profile)
    redirect_to manage_profiles_our_group_path(@group), notice: "Profile removed from group."
  end

  def add_group
    child = Current.user.groups.find(params[:group_id])
    group_group = @group.child_links.build(child_group: child)
    if group_group.save
      redirect_to group_management_path, notice: "Group added."
    else
      redirect_to group_management_path, alert: group_group.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to group_management_path, alert: "Group not found."
  end

  def remove_group
    child = @group.child_groups.find(params[:group_id])
    @group.child_groups.delete(child)
    redirect_to group_management_path, notice: "Group removed."
  rescue ActiveRecord::RecordNotFound
    redirect_to group_management_path, alert: "Group not found."
  end

  def manage_groups
    @management_tree = @group.management_tree
    @root_profiles = @group.management_root_profiles
    excluded_ids = @group.ancestor_group_ids | @group.child_group_ids | [ @group.id ]
    @available_groups = Current.user.groups
      .where.not(id: excluded_ids)
      .includes(avatar_attachment: :blob)
      .order(:name)
  end

  def toggle_visibility
    target_type = params[:target_type].to_s
    target_id = params[:target_id].to_i
    raw_path = params[:path]

    path =
      case raw_path
      when Array
        raw_path
      when String
        begin
          JSON.parse(raw_path.presence || "[]")
        rescue JSON::ParserError
          return respond_to do |format|
            format.html { redirect_to manage_groups_our_group_path(@group), alert: "Invalid path." }
            format.json { render json: { error: "Invalid path" }, status: :unprocessable_entity }
          end
        end
      else
        []
      end

    path = Array(path).map(&:to_i)
    unless %w[Group Profile].include?(target_type)
      return respond_to do |format|
        format.html { redirect_to manage_groups_our_group_path(@group), alert: "Invalid target." }
        format.json { render json: { error: "Invalid target" }, status: :unprocessable_entity }
      end
    end

    # Verify target belongs to current user
    target = target_type.constantize.find_by(id: target_id, user_id: Current.user.id)
    unless target
      return respond_to do |format|
        format.html { redirect_to manage_groups_our_group_path(@group), alert: "Not found." }
        format.json { render json: { error: "Not found" }, status: :not_found }
      end
    end

    # Verify all groups in path belong to current user and are in this tree
    if path.any?
      reachable = @group.reachable_group_ids
      unless path.all? { |gid| reachable.include?(gid) }
        return respond_to do |format|
          format.html { redirect_to manage_groups_our_group_path(@group), alert: "Not found." }
          format.json { render json: { error: "Not found" }, status: :not_found }
        end
      end
    end

    hidden = params[:hidden] == "1" || params[:hidden] == "true"
    # NOTE: Cannot use find_by(path: array) — ActiveRecord treats arrays as IN clauses,
    # which breaks JSONB equality comparison. Use explicit JSONB cast instead.
    override = InclusionOverride.where(
      group_id: @group.id,
      target_type: target_type, target_id: target_id
    ).where("path = ?::jsonb", path.to_json).first

    if hidden && !override
      InclusionOverride.create!(
        group_id: @group.id, path: path,
        target_type: target_type, target_id: target_id
      )
    elsif !hidden && override
      override.destroy!
    end

    respond_to do |format|
      format.html { redirect_to manage_groups_our_group_path(@group), notice: "Visibility updated." }
      format.json { render json: { hidden: hidden }, status: :ok }
    end
  end

  private

  def group_management_path
    manage_groups_our_group_path(@group)
  end

  def set_group
    @group = Current.user&.groups&.find_by(uuid: params[:id])
    redirect_to group_path(params[:id]) unless @group
  end

  def load_theme_options
    @personal_themes = Current.user.themes.order(:name)
    @shared_themes = Theme.shared.order(:name)
  end

  def validate_theme_choice
    theme_id = params.dig(:group, :theme_id)
    return if theme_id.blank?

    allowed_ids = Current.user.theme_ids + Theme.shared.pluck(:id)
    unless allowed_ids.include?(theme_id.to_i)
      @group ||= Current.user.groups.build
      @group.errors.add(:theme, "is not available")
      load_theme_options
      template = action_name == "create" ? :new : :edit
      render template, status: :unprocessable_entity
    end
  end

  def group_params
    params.require(:group).permit(:name, :description, :avatar, :avatar_alt_text, :created_at, :labels_text, :theme_id).tap do |p|
      if p[:created_at].blank? ||
          !p[:created_at].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\z/) ||
          (@group&.created_at && p[:created_at] == @group.created_at.utc.strftime("%Y-%m-%dT%H:%M"))
        p.delete(:created_at)
      end
    end
  end
end
