class Group < ApplicationRecord
  include HasAvatar
  include HasLabels

  belongs_to :user
  belongs_to :theme, optional: true
  belongs_to :copied_from, class_name: "Group", optional: true
  has_many :copies, class_name: "Group", foreign_key: :copied_from_id, dependent: :nullify
  has_many :group_profiles, dependent: :destroy
  has_many :profiles, -> { order(:name) }, through: :group_profiles

  has_many :parent_links, class_name: "GroupGroup", foreign_key: :child_group_id, dependent: :destroy
  has_many :child_links, class_name: "GroupGroup", foreign_key: :parent_group_id, dependent: :destroy
  has_many :parent_groups, through: :parent_links, source: :parent_group
  has_many :child_groups, through: :child_links, source: :child_group
  has_many :inclusion_overrides, dependent: :destroy

  before_create :generate_uuid

  validates :name, presence: true
  validates :uuid, uniqueness: true
  validates :created_at, comparison: { less_than_or_equal_to: -> { Time.current + 1.minute }, message: "can't be in the future" }, allow_nil: true, if: :created_at_changed?

  def to_param
    uuid
  end

  # Returns copies of this group that have ALL of the given labels.
  # Follows the full copy lineage chain (copies of copies) using a recursive CTE,
  # so a grandchild copy (A → B → C) is found when searching from A.
  def copies_with_labels(labels)
    sql = <<~SQL.squish
      WITH RECURSIVE copy_tree AS (
        SELECT id FROM groups WHERE copied_from_id = :root_id AND user_id = :user_id
        UNION
        SELECT g.id FROM groups g
        INNER JOIN copy_tree ct ON g.copied_from_id = ct.id
        WHERE g.user_id = :user_id
      )
      SELECT id FROM copy_tree
    SQL
    all_copy_ids = Group.connection.select_values(
      Group.sanitize_sql([ sql, root_id: id, user_id: user_id ])
    ).map(&:to_i)
    Group.where(id: all_copy_ids, user_id: user_id).where("labels @> ?", labels.to_json)
  end

  # Scans the descendant tree depth-first and returns an array of conflict
  # hashes for sub-groups and profiles that already have copies with ALL of
  # the given labels.
  # The root group itself is not checked (it's the source being duplicated),
  # but its profiles are checked.
  # Group conflicts come first (depth-first order), then profile conflicts.
  # Profile conflicts include container_group_ids so the wizard can determine
  # which profile conflicts are still relevant after group resolutions.
  def scan_for_conflicts(labels)
    conflicts = []
    all_ids = reachable_group_ids - [ id ]

    if all_ids.any?
      children_map = build_children_map([ id ] + all_ids)
      groups_by_id = Group.where(id: all_ids).index_by(&:id)
      walk_tree_for_conflicts(id, children_map, groups_by_id, labels, conflicts)
    end

    # Profile conflicts: check all profiles in the full tree (including root)
    all_tree_ids = [ id ] + all_ids
    profile_group_pairs = GroupProfile.where(group_id: all_tree_ids).pluck(:profile_id, :group_id)
    profile_container_map = profile_group_pairs.group_by(&:first)
                                               .transform_values { |pairs| pairs.map(&:last) }

    if profile_container_map.any?
      Profile.where(id: profile_container_map.keys, user_id: user_id).order(:name).each do |profile|
        existing = profile.copies_with_labels(labels).first
        next unless existing

        conflicts << {
          original_id: profile.id,
          original_type: "Profile",
          name: profile.name,
          existing_copy_id: existing.id,
          existing_copy_name: existing.name,
          existing_copy_labels: existing.labels,
          container_group_ids: profile_container_map[profile.id]
        }
      end
    end

    conflicts
  end

  # Deep-copies this group and its entire tree.
  #
  # resolutions: a Hash of { original_group_id (string) => "reuse" | "copy" }
  #   - "reuse": link the existing copy into the new tree instead of copying
  #   - "copy" (or absent): create a fresh copy
  #
  # profile_resolutions: a Hash of { original_profile_id (string) => "reuse" | "copy" }
  #   - "reuse": link the existing copy instead of creating a new one
  #   - "copy" (or absent): create a fresh copy
  #
  # For reused groups:
  #   - Their profiles and overrides are left as-is
  #   - They are linked as children in the new tree structure
  #
  # For freshly copied groups:
  #   - New UUID, new labels, avatar copied
  #   - All profiles inside are freshly copied (unless individually reused)
  #   - Inclusion overrides are recreated with remapped paths
  #   - copied_from_id is set to the original's ID
  #
  # Everything happens in a single transaction.
  def deep_duplicate(new_labels: [], resolutions: {}, profile_resolutions: {})
    group_map = {}   # old_id => new_or_reused_group
    profile_map = {} # old_id => new_or_reused_profile
    reused_group_ids = Set.new
    reused_profile_ids = Set.new
    skip_ids = Set.new

    all_ids = reachable_group_ids
    groups_to_process = Group.where(id: all_ids, user_id: user_id)
                             .includes(:profiles, avatar_attachment: :blob)
    groups_by_id = groups_to_process.index_by(&:id)
    children_map = build_children_map(all_ids)

    # Phase A: Walk tree depth-first, building group map while respecting resolutions.
    # When a group is reused, all its descendants are skipped.
    build_group_map_depth_first(
      id, children_map, groups_by_id, new_labels, resolutions,
      group_map, reused_group_ids, skip_ids
    )

    # Phase B: Build profile map for freshly-copied groups only.
    # Profiles that appear in multiple fresh groups are copied once.
    fresh_group_ids = group_map.keys.reject { |gid| reused_group_ids.include?(gid) || skip_ids.include?(gid) }
    profile_ids = GroupProfile.where(group_id: fresh_group_ids).pluck(:profile_id).uniq
    profiles_to_copy = Profile.where(id: profile_ids, user_id: user_id)
                              .includes(avatar_attachment: :blob)
    profiles_by_id = profiles_to_copy.index_by(&:id)

    profiles_to_copy.each do |original_profile|
      if profile_resolutions[original_profile.id.to_s] == "reuse"
        existing_copy = original_profile.copies_with_labels(new_labels).first
        if existing_copy
          profile_map[original_profile.id] = existing_copy
          reused_profile_ids << original_profile.id
          next
        end
      end

      new_profile = original_profile.dup
      new_profile.uuid = PluralProfilesUuid.generate
      new_profile.labels = new_labels
      new_profile.copied_from = original_profile
      profile_map[original_profile.id] = new_profile
    end

    # Phase C: Execute everything in a transaction.
    # Avatar copying is intentionally done AFTER the transaction (below) because
    # Active Storage writes the blob file via an after_create_commit callback —
    # if attach is called inside a transaction the IO is read after commit, by
    # which point any tempfile opened inside the transaction would already be
    # closed, causing "IOError: closed stream".
    ActiveRecord::Base.transaction do
      # Save new groups (skip reused — they already exist)
      group_map.each do |old_id, group|
        next if skip_ids.include?(old_id)
        group.save! if group.new_record?
      end

      # Save new profiles (skip reused — they already exist)
      profile_map.each do |old_id, profile|
        profile.save! unless reused_profile_ids.include?(old_id)
      end

      # Recreate group_groups edges for non-skipped groups
      GroupGroup.where(parent_group_id: group_map.keys, child_group_id: group_map.keys).each do |gg|
        next if skip_ids.include?(gg.parent_group_id) || skip_ids.include?(gg.child_group_id)
        new_parent = group_map[gg.parent_group_id]
        new_child = group_map[gg.child_group_id]
        next unless new_parent && new_child
        GroupGroup.create!(parent_group: new_parent, child_group: new_child)
      end

      # Recreate group_profiles for freshly-copied groups
      GroupProfile.where(group_id: fresh_group_ids).each do |gp|
        new_group = group_map[gp.group_id]
        new_profile = profile_map[gp.profile_id]
        next unless new_group && new_profile
        GroupProfile.create!(group: new_group, profile: new_profile)
      end

      # Recreate inclusion overrides for freshly-copied groups only
      InclusionOverride.where(group_id: fresh_group_ids).each do |override|
        new_root = group_map[override.group_id]
        next unless new_root

        new_path = override.path.map { |gid| group_map[gid]&.id }.compact
        next if new_path.length != override.path.length

        new_target_id = case override.target_type
        when "Group"   then group_map[override.target_id]&.id
        when "Profile" then profile_map[override.target_id]&.id
        end
        next unless new_target_id

        InclusionOverride.create!(
          group: new_root,
          path: new_path,
          target_type: override.target_type,
          target_id: new_target_id
        )
      end
    end

    # Copy avatars after the transaction so Active Storage's after_create_commit
    # callback can read the IO without hitting a closed stream.
    group_map.each do |old_id, new_group|
      next if reused_group_ids.include?(old_id) || skip_ids.include?(old_id)
      original = groups_by_id[old_id]
      duplicate_avatar(original, new_group) if original&.avatar&.attached?
    end

    profile_map.each do |old_id, new_profile|
      next if reused_profile_ids.include?(old_id)
      original = profiles_by_id[old_id]
      duplicate_avatar(original, new_profile) if original&.avatar&.attached?
    end

    group_map[id] # Return the new root group
  end

  # All group IDs reachable from this group via group_groups edges (recursive).
  # Used for circular-reference validation, UI exclusion lists, and tree building.
  def reachable_group_ids
    sql = <<~SQL.squish
      WITH RECURSIVE tree AS (
        SELECT CAST(:root_id AS bigint) AS id
        UNION
        SELECT gg.child_group_id AS id
        FROM group_groups gg
        INNER JOIN tree ON tree.id = gg.parent_group_id
      )
      SELECT DISTINCT id FROM tree
    SQL
    Group.connection.select_values(
      Group.sanitize_sql([ sql, root_id: id ])
    ).map(&:to_i)
  end

  alias_method :descendant_group_ids, :reachable_group_ids

  # All group IDs in the ancestor tree (this group + all parents, recursive).
  # Used to prevent circular references in the UI before validation.
  def ancestor_group_ids
    sql = <<~SQL.squish
      WITH RECURSIVE tree AS (
        SELECT CAST(:root_id AS bigint) AS id
        UNION
        SELECT gg.parent_group_id AS id
        FROM group_groups gg
        INNER JOIN tree ON tree.id = gg.child_group_id
      )
      SELECT id FROM tree
    SQL
    Group.connection.select_values(
      Group.sanitize_sql([ sql, root_id: id ])
    ).map(&:to_i)
  end

  # Collect all descendant groups (not including self).
  # Single recursive CTE query.
  def all_child_groups
    Group.where(id: descendant_group_ids).where.not(id: id)
  end

  # Build a depth-first ordered list of all descendant groups.
  # Each group has its profiles and avatars eager-loaded.
  # Inclusion overrides are applied during traversal.
  def descendant_sections
    all_ids = reachable_group_ids - [ id ]
    return [] if all_ids.empty?

    overrides = overrides_index
    children_map = build_children_map([ id ] + all_ids)

    # Compute which groups will actually be traversed (respecting overrides)
    traversed_ids = Set.new
    collect_traversed_group_ids_recursive(id, [], children_map, overrides, traversed_ids)

    groups_by_id = Group.where(id: traversed_ids.to_a)
                        .includes(profiles: { avatar_attachment: :blob }, avatar_attachment: :blob)
                        .index_by(&:id)

    walk_descendants(id, [], children_map, groups_by_id, overrides)
  end

  # Build a nested tree of all descendant groups for tree-view navigation.
  # Returns an array of nodes: { group:, profiles:, children: }
  # Each profile entry is a hash { profile:, repeated: } so the view can
  # visually distinguish profiles that appear more than once in the tree.
  # Inclusion overrides are applied during traversal using path-scoping.
  def descendant_tree(seen_profile_ids: nil)
    all_ids = reachable_group_ids - [ id ]
    return [] if all_ids.empty?

    overrides = overrides_index
    children_map = build_children_map([ id ] + all_ids)

    # Compute which groups will actually be traversed (respecting overrides)
    traversed_ids = Set.new
    collect_traversed_group_ids_recursive(id, [], children_map, overrides, traversed_ids)

    groups_by_id = Group.where(id: traversed_ids.to_a)
                        .includes(profiles: { avatar_attachment: :blob }, avatar_attachment: :blob)
                        .index_by(&:id)

    seen_profile_ids ||= Set.new
    build_tree(id, [], children_map, groups_by_id, seen_profile_ids, overrides)
  end

  # Profiles visible when this group is reached via a specific traversal path
  # from root_group_id. Performs a single targeted DB query — no tree traversal.
  # path is an array of integer group IDs (the container_path including this group's id).
  def profiles_visible_at_path(path, root_group_id:)
    hidden_ids = InclusionOverride
      .where(group_id: root_group_id, target_type: "Profile")
      .where("path = ?::jsonb", path.to_json)
      .pluck(:target_id)
    profiles.where.not(id: hidden_ids)
  end

  # Root-level profiles visible in the public view, filtering out
  # those hidden by inclusion overrides at path=[].
  def visible_root_profiles
    hidden_profile_ids = inclusion_overrides
      .where(target_type: "Profile")
      .where("path = '[]'::jsonb")
      .pluck(:target_id)
    profiles.where.not(id: hidden_profile_ids).order_by_name_and_labels
  end

  # Collect all profiles from this group and all descendant groups,
  # respecting path-scoped inclusion overrides.
  # Walks the tree depth-first, checking overrides at each path.
  # Profiles may appear in multiple sub-groups; the result is de-duplicated.
  def all_profiles
    all_ids = reachable_group_ids - [ id ]
    overrides = overrides_index

    # Root group's own profiles, filtered by root-level overrides
    root_profile_ids = profiles.pluck(:id)
    visible_profile_ids = Set.new(
      root_profile_ids.reject { |pid| overrides.include?([ [], "Profile", pid ]) }
    )

    if all_ids.any?
      children_map = build_children_map([ id ] + all_ids)
      groups_by_id = Group.where(id: all_ids)
                          .includes(:profiles)
                          .index_by(&:id)

      collect_visible_profile_ids(id, [], children_map, groups_by_id, overrides, visible_profile_ids)
    end

    Profile.where(id: visible_profile_ids.to_a)
  end

  # Build a preview tree for the duplication confirmation page.
  # Shows the full tree annotated with whether each group/profile
  # will be newly created or reused from an existing copy, and
  # whether each item is hidden via inclusion overrides.
  # Returns an array of nodes:
  #   { group:, action:, directly_reused:, reuse_target:, hidden:, cascade_hidden:, profiles:, children: }
  # Profiles carry:
  #   { profile:, action:, hidden:, cascade_hidden: }
  def duplication_preview_tree(labels:, resolutions:, profile_resolutions: {})
    all_ids = reachable_group_ids
    groups_by_id = Group.where(id: all_ids)
                        .includes(:profiles, avatar_attachment: :blob)
                        .index_by(&:id)
    children_map = build_children_map(all_ids)
    overrides = overrides_index

    reused_ids = resolutions.select { |_, v| v == "reuse" }.keys.map(&:to_i).to_set

    # Validate that reuse targets still exist; silently downgrade stale ones to "new"
    # so the preview never claims a copy will be reused when it no longer exists.
    reused_ids.select! do |rid|
      group = groups_by_id[rid]
      group && group.copies_with_labels(labels).first.present?
    end

    expanded_reused_ids = Set.new(reused_ids)
    reused_ids.each do |rid|
      group = groups_by_id[rid]
      next unless group
      (group.descendant_group_ids - [ group.id ]).each { |did| expanded_reused_ids << did }
    end

    build_duplication_preview(id, [], children_map, groups_by_id, labels, reused_ids, expanded_reused_ids, overrides, false, profile_resolutions)
  end

  # Build a tree for the management UI. Shows ALL groups and profiles
  # (regardless of overrides), with hidden/cascade-hidden flags and path data
  # so the view can render checkboxes for toggling visibility.
  # Returns an array of nodes:
  #   { group:, profiles:, children:, hidden:, cascade_hidden:, path:, container_path: }
  # Profiles within each node carry:
  #   { profile:, hidden:, cascade_hidden:, container_path: }
  def management_tree
    all_ids = reachable_group_ids - [ id ]
    return [] if all_ids.empty?

    overrides = overrides_index
    children_map = build_children_map([ id ] + all_ids)

    groups_by_id = Group.where(id: all_ids)
                        .includes(profiles: { avatar_attachment: :blob }, avatar_attachment: :blob)
                        .index_by(&:id)

    build_management_tree(id, [], children_map, groups_by_id, overrides, false)
  end

  # Root-level profiles for the management UI, with hidden/cascade-hidden flags.
  # Returns an array of hashes:
  #   { profile:, hidden:, cascade_hidden:, container_path: }
  def management_root_profiles
    overrides = overrides_index
    profiles.includes(avatar_attachment: :blob).order_by_name_and_labels.map do |profile|
      {
        profile: profile,
        hidden: overrides.include?([ [], "Profile", profile.id ]),
        cascade_hidden: false,
        container_path: []
      }
    end
  end

  private

  # Returns a Set of [path, target_type, target_id] tuples
  # for quick lookups during tree traversal.
  # path is an array of group IDs (may be empty for root-level items).
  def overrides_index
    InclusionOverride.where(group_id: id)
      .pluck(:path, :target_type, :target_id)
      .map { |path, type, tid| [ Array(path).map(&:to_i), type, tid ] }
      .to_set
  end

  # Build the children_map used by tree traversal methods.
  # Returns { parent_group_id => [ { id: child_group_id } ] }
  def build_children_map(parent_ids)
    GroupGroup.where(parent_group_id: parent_ids)
      .pluck(:parent_group_id, :child_group_id)
      .group_by(&:first)
      .transform_values { |rows| rows.map { |r| { id: r[1] } } }
  end

  # -- Flat descendant list (descendant_sections) ----------------------------

  def walk_descendants(parent_id, current_path, children_map, groups_by_id, overrides)
    (children_map[parent_id] || [])
      .filter_map { |entry| groups_by_id[entry[:id]] ? [ groups_by_id[entry[:id]], entry ] : nil }
      .reject { |g, _| overrides.include?([ current_path, "Group", g.id ]) }
      .sort_by { |g, _| g.name_and_label_sort_key }
      .flat_map do |g, _entry|
        child_path = current_path + [ g.id ]
        [ g, *walk_descendants(g.id, child_path, children_map, groups_by_id, overrides) ]
      end
  end

  # -- Nested tree (descendant_tree) ----------------------------------------

  def build_tree(parent_id, current_path, children_map, groups_by_id, seen_profile_ids, overrides)
    (children_map[parent_id] || [])
      .filter_map { |entry| groups_by_id[entry[:id]] ? [ groups_by_id[entry[:id]], entry ] : nil }
      .reject { |g, _| overrides.include?([ current_path, "Group", g.id ]) }
      .sort_by { |g, _| g.name_and_label_sort_key }
      .map do |g, _entry|
        child_path = current_path + [ g.id ]
        visible_profiles = g.profiles.reject { |p| overrides.include?([ child_path, "Profile", p.id ]) }

        {
          group: g,
          profiles: tag_profiles(visible_profiles, seen_profile_ids),
          children: build_tree(g.id, child_path, children_map, groups_by_id, seen_profile_ids, overrides),
          path: child_path
        }
      end
  end

  # -- Duplication preview tree (duplication_preview_tree) ------------------

  def build_duplication_preview(parent_id, current_path, children_map, groups_by_id, labels, reused_ids, expanded_reused_ids, overrides, ancestor_hidden, profile_resolutions = {})
    (children_map[parent_id] || [])
      .filter_map { |entry| groups_by_id[entry[:id]] ? [ groups_by_id[entry[:id]], entry ] : nil }
      .sort_by { |g, _| g.name_and_label_sort_key }
      .map do |g, _entry|
        is_reused = expanded_reused_ids.include?(g.id)
        is_directly_reused = reused_ids.include?(g.id)
        action = is_reused ? "reuse" : "new"
        reuse_target = is_directly_reused ? g.copies_with_labels(labels).first : nil
        hidden = overrides.include?([ current_path, "Group", g.id ])
        effectively_hidden = hidden || ancestor_hidden
        child_path = current_path + [ g.id ]

        profile_entries = g.profiles.map do |profile|
          if is_reused
            profile_action = "reuse"
            directly_reused_profile = false
            reuse_target_profile = nil
          elsif profile_resolutions[profile.id.to_s] == "reuse"
            reuse_target_profile = profile.copies_with_labels(labels).first
            if reuse_target_profile
              profile_action = "reuse"
              directly_reused_profile = true
            else
              # Copy no longer exists; downgrade to "new" so the preview is accurate
              profile_action = "new"
              directly_reused_profile = false
              reuse_target_profile = nil
            end
          else
            profile_action = "new"
            directly_reused_profile = false
            reuse_target_profile = nil
          end

          {
            profile: profile,
            action: profile_action,
            directly_reused: directly_reused_profile,
            reuse_target: reuse_target_profile,
            hidden: overrides.include?([ child_path, "Profile", profile.id ]),
            cascade_hidden: effectively_hidden
          }
        end

        {
          group: g,
          action: action,
          directly_reused: is_directly_reused,
          reuse_target: reuse_target,
          hidden: hidden,
          cascade_hidden: ancestor_hidden,
          profiles: profile_entries,
          children: build_duplication_preview(g.id, child_path, children_map, groups_by_id, labels, reused_ids, expanded_reused_ids, overrides, effectively_hidden, profile_resolutions)
        }
      end
  end

  # -- Management tree (management_tree) ------------------------------------

  def build_management_tree(parent_id, current_path, children_map, groups_by_id, overrides, ancestor_hidden)
    (children_map[parent_id] || [])
      .filter_map { |entry| groups_by_id[entry[:id]] ? [ groups_by_id[entry[:id]], entry ] : nil }
      .sort_by { |g, _| g.name_and_label_sort_key }
      .map do |g, _entry|
        hidden = overrides.include?([ current_path, "Group", g.id ])
        effectively_hidden = hidden || ancestor_hidden
        child_path = current_path + [ g.id ]

        profile_entries = g.profiles.map do |profile|
          {
            profile: profile,
            hidden: overrides.include?([ child_path, "Profile", profile.id ]),
            cascade_hidden: effectively_hidden,
            container_path: child_path
          }
        end

        {
          group: g,
          profiles: profile_entries,
          children: build_management_tree(g.id, child_path, children_map, groups_by_id, overrides, effectively_hidden),
          hidden: hidden,
          cascade_hidden: ancestor_hidden,
          path: current_path,
          container_path: child_path
        }
      end
  end

  # -- Profile collection (all_profiles) ------------------------------------

  # Walk the tree depth-first collecting visible profile IDs,
  # respecting path-scoped overrides.
  def collect_visible_profile_ids(parent_id, current_path, children_map, groups_by_id, overrides, result)
    (children_map[parent_id] || []).each do |entry|
      next if overrides.include?([ current_path, "Group", entry[:id] ])

      child_path = current_path + [ entry[:id] ]
      group = groups_by_id[entry[:id]]
      next unless group

      group.profiles.each do |profile|
        result.add(profile.id) unless overrides.include?([ child_path, "Profile", profile.id ])
      end

      collect_visible_profile_ids(entry[:id], child_path, children_map, groups_by_id, overrides, result)
    end
  end

  # -- Traversed group ID collection ----------------------------------------

  # Compute the set of descendant group IDs that will actually be visited
  # during traversal, respecting path-scoped overrides.
  def collect_traversed_group_ids_recursive(parent_id, current_path, children_map, overrides, result)
    (children_map[parent_id] || []).each do |entry|
      next if overrides.include?([ current_path, "Group", entry[:id] ])

      result.add(entry[:id])
      child_path = current_path + [ entry[:id] ]
      collect_traversed_group_ids_recursive(entry[:id], child_path, children_map, overrides, result)
    end
  end

  # -- Shared helpers -------------------------------------------------------

  # Tag each profile with :repeated based on whether it has been seen before.
  # Mutates seen_profile_ids in place so later nodes see earlier occurrences.
  def tag_profiles(profiles, seen_profile_ids)
    profiles.map do |profile|
      repeated = seen_profile_ids.include?(profile.id)
      seen_profile_ids.add(profile.id)
      { profile: profile, repeated: repeated }
    end
  end

  # -- Duplication helpers --------------------------------------------------

  # Walk the tree depth-first looking for groups that already have copies
  # with ALL of the given labels. Returns conflicts in depth-first order.
  def walk_tree_for_conflicts(parent_id, children_map, groups_by_id, labels, conflicts)
    (children_map[parent_id] || []).each do |entry|
      group = groups_by_id[entry[:id]]
      next unless group

      existing = group.copies_with_labels(labels).first
      if existing
        conflicts << {
          original_id: group.id,
          original_type: "Group",
          name: group.name,
          existing_copy_id: existing.id,
          existing_copy_name: existing.name,
          existing_copy_labels: existing.labels
        }
      end

      walk_tree_for_conflicts(group.id, children_map, groups_by_id, labels, conflicts)
    end
  end

  # Walk the tree depth-first, building a group map. When a group is resolved
  # as "reuse", its existing copy is linked and all descendants are skipped.
  def build_group_map_depth_first(parent_id, children_map, groups_by_id, new_labels, resolutions, group_map, reused_group_ids, skip_ids)
    original = groups_by_id[parent_id]
    return unless original

    resolution = resolutions[parent_id.to_s]
    if resolution == "reuse"
      existing_copy = original.copies_with_labels(new_labels).first
      if existing_copy
        group_map[parent_id] = existing_copy
        reused_group_ids << parent_id
        # Mark all descendants as skipped
        mark_descendants_as_skipped(parent_id, children_map, skip_ids)
        return
      end
    end

    # Fresh copy (or root group being duplicated)
    unless group_map.key?(parent_id)
      new_group = original.dup
      new_group.uuid = PluralProfilesUuid.generate
      new_group.labels = new_labels
      new_group.copied_from = original
      group_map[parent_id] = new_group
    end

    (children_map[parent_id] || []).each do |entry|
      build_group_map_depth_first(
        entry[:id], children_map, groups_by_id, new_labels, resolutions,
        group_map, reused_group_ids, skip_ids
      )
    end
  end

  # Recursively mark all descendants of a group as skipped.
  def mark_descendants_as_skipped(parent_id, children_map, skip_ids)
    (children_map[parent_id] || []).each do |entry|
      skip_ids << entry[:id]
      mark_descendants_as_skipped(entry[:id], children_map, skip_ids)
    end
  end

  # Copy an Active Storage avatar from source to target.
  # Uses blob.open (tempfile-backed) to stream the download without loading
  # the entire file into memory. Must be called outside a transaction so that
  # Active Storage's after_create_commit callback can read the IO synchronously
  # before the tempfile is closed.
  def duplicate_avatar(source, target)
    return unless source.avatar.attached?
    blob = source.avatar.blob
    blob.open do |tempfile|
      target.avatar.attach(
        io: tempfile,
        filename: blob.filename,
        content_type: blob.content_type
      )
    end
  end

  def generate_uuid
    self.uuid = PluralProfilesUuid.generate
  end
end
