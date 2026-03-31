class Our::GroupsController < ApplicationController
  include OurSidebar
  allow_unauthenticated_access only: :show
  before_action :resume_session, only: :show
  before_action :set_group, only: %i[ show edit update destroy manage_profiles add_profile remove_profile add_group remove_group regenerate_uuid manage_groups toggle_visibility duplicate duplicate_scan duplicate_resolve duplicate_resolve_post duplicate_confirm duplicate_execute ]
  before_action :validate_theme_choice, only: %i[create update]

  def index
    @groups = Current.user.groups.order_by_name_and_labels
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
    @available_profiles = Current.user.profiles.where.not(id: @group.profile_ids).order_by_name_and_labels
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
      .order_by_name_and_labels
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

  # -- Duplication wizard --------------------------------------------------

  # Step 1: Show label input form
  def duplicate
  end

  # Process Step 1: scan for conflicts and redirect
  def duplicate_scan
    labels = params[:labels_text].to_s.split(",").map(&:strip).reject(&:blank?).uniq

    if labels.empty?
      flash.now[:alert] = "Please enter at least one label for the copies."
      render :duplicate, status: :unprocessable_entity
      return
    end

    conflicts = @group.scan_for_conflicts(labels)

    group_conflicts = conflicts.select { |c| c[:original_type] == "Group" }
    profile_conflicts = conflicts.select { |c| c[:original_type] == "Profile" }

    session[:duplication_wizard] = {
      "source_group_id" => @group.id,
      "labels" => labels,
      "group_conflicts" => group_conflicts.map { |c| c.transform_keys(&:to_s) },
      "profile_conflicts" => profile_conflicts.map { |c| c.transform_keys(&:to_s) },
      "resolutions" => {},
      "profile_resolutions" => {},
      "current_conflict_index" => 0,
      "phase" => "groups"
    }

    if group_conflicts.any?
      redirect_to duplicate_resolve_our_group_path(@group)
    else
      advance_to_profile_conflicts_or_confirm(session[:duplication_wizard])
    end
  end

  # Step 2: Show one conflict at a time (group or profile)
  def duplicate_resolve
    wizard = session[:duplication_wizard]
    unless wizard && wizard["source_group_id"] == @group.id
      redirect_to duplicate_our_group_path(@group), alert: "Please start the duplication process again."
      return
    end

    load_conflict_view_vars(wizard)
  end

  # Process one conflict resolution and advance
  def duplicate_resolve_post
    wizard = session[:duplication_wizard]
    unless wizard && wizard["source_group_id"] == @group.id
      redirect_to duplicate_our_group_path(@group), alert: "Please start the duplication process again."
      return
    end

    unless %w[reuse copy].include?(params[:resolution])
      load_conflict_view_vars(wizard)
      flash.now[:alert] = "Please select an option before continuing."
      render :duplicate_resolve, status: :unprocessable_entity
      return
    end

    phase = wizard["phase"] || "groups"

    if phase == "groups"
      resolve_group_conflict(wizard)
    else
      resolve_profile_conflict(wizard)
    end
  end

  # Step 3: Show confirmation summary
  def duplicate_confirm
    wizard = session[:duplication_wizard]
    unless wizard && wizard["source_group_id"] == @group.id
      redirect_to duplicate_our_group_path(@group), alert: "Please start the duplication process again."
      return
    end

    @labels = wizard["labels"]
    @resolutions = wizard["resolutions"]
    @profile_resolutions = wizard["profile_resolutions"] || {}
    @source = @group

    # Build the full preview tree with new/reuse annotations
    @preview_tree = @group.duplication_preview_tree(
      labels: @labels, resolutions: @resolutions, profile_resolutions: @profile_resolutions
    )

    # Root-level profiles, with hidden flags from overrides
    overrides = @group.send(:overrides_index)
    @root_profiles = @group.profiles
                           .includes(avatar_attachment: :blob)
                           .order(:name)
                           .map do |p|
                             if @profile_resolutions[p.id.to_s] == "reuse"
                               reuse_target = p.copies_with_labels(@labels).first
                               {
                                 profile: p,
                                 action: "reuse",
                                 directly_reused: true,
                                 reuse_target: reuse_target,
                                 hidden: overrides.include?([ [], "Profile", p.id ]),
                                 cascade_hidden: false
                               }
                             else
                               {
                                 profile: p,
                                 action: "new",
                                 directly_reused: false,
                                 reuse_target: nil,
                                 hidden: overrides.include?([ [], "Profile", p.id ]),
                                 cascade_hidden: false
                               }
                             end
                           end
  end

  # Execute the duplication
  def duplicate_execute
    wizard = session[:duplication_wizard]
    unless wizard && wizard["source_group_id"] == @group.id
      redirect_to duplicate_our_group_path(@group), alert: "Please start the duplication process again."
      return
    end

    labels = wizard["labels"]
    resolutions = wizard["resolutions"]
    profile_resolutions = wizard["profile_resolutions"] || {}

    new_group = @group.deep_duplicate(
      new_labels: labels, resolutions: resolutions, profile_resolutions: profile_resolutions
    )
    session.delete(:duplication_wizard)
    redirect_to our_group_path(new_group), notice: "Group duplicated with all sub-groups and profiles."
  end

  private

  def group_management_path
    manage_groups_our_group_path(@group)
  end

  # -- Duplication wizard helpers ------------------------------------------

  def resolve_group_conflict(wizard)
    index = wizard["current_conflict_index"]
    conflict = wizard["group_conflicts"][index]

    # Record the user's choice
    wizard["resolutions"][conflict["original_id"].to_s] = params[:resolution]

    # If user chose "reuse", skip conflicts for descendants of this group
    if params[:resolution] == "reuse"
      reused_group = Group.find(conflict["original_id"])
      descendant_ids = (reused_group.descendant_group_ids - [ reused_group.id ]).map(&:to_s).to_set
      # Mark descendant conflicts as implicitly resolved
      wizard["group_conflicts"].each_with_index do |c, i|
        next if i <= index
        if descendant_ids.include?(c["original_id"].to_s)
          wizard["resolutions"][c["original_id"].to_s] = "reuse"
        end
      end
    end

    # Find next unresolved group conflict
    next_index = ((index + 1)...wizard["group_conflicts"].length).find do |i|
      !wizard["resolutions"].key?(wizard["group_conflicts"][i]["original_id"].to_s)
    end

    if next_index
      wizard["current_conflict_index"] = next_index
      session[:duplication_wizard] = wizard
      redirect_to duplicate_resolve_our_group_path(@group)
    else
      # All group conflicts resolved — advance to profile conflicts or confirm
      session[:duplication_wizard] = wizard
      advance_to_profile_conflicts_or_confirm(wizard)
    end
  end

  def resolve_profile_conflict(wizard)
    index = wizard["current_profile_conflict_index"]
    active = wizard["active_profile_conflicts"]
    conflict = active[index]

    # Record the user's choice
    wizard["profile_resolutions"][conflict["original_id"].to_s] = params[:resolution]

    # Find next profile conflict
    next_index = index + 1
    if next_index < active.length
      wizard["current_profile_conflict_index"] = next_index
      session[:duplication_wizard] = wizard
      redirect_to duplicate_resolve_our_group_path(@group)
    else
      session[:duplication_wizard] = wizard
      redirect_to duplicate_confirm_our_group_path(@group)
    end
  end

  # After all group conflicts are resolved, compute which profile conflicts
  # are still relevant (the profile appears in at least one freshly-copied group)
  # and either start the profile conflict phase or go to confirm.
  def advance_to_profile_conflicts_or_confirm(wizard)
    profile_conflicts = wizard["profile_conflicts"] || []

    if profile_conflicts.any?
      # Compute all reused + skipped group IDs
      reused_gids = Set.new
      wizard["resolutions"].each do |id_str, res|
        next unless res == "reuse"
        gid = id_str.to_i
        reused_gids << gid
        group = Group.find_by(id: gid)
        if group
          (group.descendant_group_ids - [ group.id ]).each { |did| reused_gids << did }
        end
      end

      # A profile conflict is relevant if the profile appears in at least one
      # group that is NOT reused/skipped (root group is always fresh)
      relevant = profile_conflicts.select do |pc|
        container_ids = (pc["container_group_ids"] || []).map(&:to_i)
        container_ids.any? { |gid| !reused_gids.include?(gid) }
      end

      if relevant.any?
        wizard["phase"] = "profiles"
        wizard["active_profile_conflicts"] = relevant
        wizard["current_profile_conflict_index"] = 0
        session[:duplication_wizard] = wizard
        redirect_to duplicate_resolve_our_group_path(@group)
        return
      end
    end

    session[:duplication_wizard] = wizard
    redirect_to duplicate_confirm_our_group_path(@group)
  end

  def load_conflict_view_vars(wizard)
    phase = wizard["phase"] || "groups"

    if phase == "groups"
      index = wizard["current_conflict_index"]
      @conflict = wizard["group_conflicts"][index]
      @conflict_number = index + 1
      @total_conflicts = wizard["group_conflicts"].length
      @conflict_phase_label = "Group question"
    else
      index = wizard["current_profile_conflict_index"]
      active = wizard["active_profile_conflicts"]
      @conflict = active[index]
      @conflict_number = index + 1
      @total_conflicts = active.length
      @conflict_phase_label = "Profile question"
    end

    conflict_type = @conflict["original_type"]
    unless %w[Group Profile].include?(conflict_type)
      session.delete(:duplication_wizard)
      redirect_to duplicate_our_group_path(@group), alert: "Something went wrong. Please start the duplication process again."
      return
    end

    klass = conflict_type.constantize
    @original = klass.find(@conflict["original_id"])
    @existing_copy = klass.find(@conflict["existing_copy_id"])
    @labels = wizard["labels"]
    @source = @group
    @conflict_type = conflict_type
  end

  def set_group
    @group = Current.user&.groups&.find_by(uuid: params[:id])
    redirect_to group_path(params[:id]) unless @group
  end

  def load_theme_options
    @our_themes = Current.user.themes.order(:name)
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
