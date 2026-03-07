class Group < ApplicationRecord
  include HasAvatar

  belongs_to :user
  has_many :group_profiles, dependent: :destroy
  has_many :profiles, -> { order(:name) }, through: :group_profiles

  has_many :parent_links, class_name: "GroupGroup", foreign_key: :child_group_id, dependent: :destroy
  has_many :child_links, class_name: "GroupGroup", foreign_key: :parent_group_id, dependent: :destroy
  has_many :parent_groups, through: :parent_links, source: :parent_group
  has_many :child_groups, through: :child_links, source: :child_group
  has_many :inclusion_overrides, foreign_key: :target_group_id, dependent: :destroy, inverse_of: :target_group

  before_create :generate_uuid

  validates :name, presence: true
  validates :uuid, uniqueness: true
  validates :created_at, comparison: { less_than_or_equal_to: -> { Time.current + 1.minute }, message: "can't be in the future" }, allow_nil: true, if: :created_at_changed?

  def to_param
    uuid
  end

  # All group IDs in the descendant tree (this group + all children, recursive).
  # Uses a single recursive CTE query instead of N+1 queries per nesting level.
  # Overlapping children are included but recursion stops at them — their own
  # children are not pulled into this group's descendants.
  def descendant_group_ids
    sql = <<~SQL.squish
      WITH RECURSIVE tree AS (
        SELECT CAST(:root_id AS bigint) AS id, true AS recurse_further
        UNION ALL
         SELECT gg.child_group_id AS id,
           (gg.subgroup_inclusion_mode = 'all') AS recurse_further
        FROM group_groups gg
        INNER JOIN tree t ON t.id = gg.parent_group_id
        WHERE t.recurse_further = true
      )
      SELECT DISTINCT id FROM tree
      UNION
      SELECT DISTINCT (jsonb_array_elements_text(gg.included_subgroup_ids))::bigint AS id
      FROM group_groups gg
      INNER JOIN tree t ON t.id = gg.parent_group_id
      WHERE gg.subgroup_inclusion_mode = 'selected' AND t.recurse_further = true
    SQL
    Group.connection.select_values(
      Group.sanitize_sql([ sql, root_id: id ])
    ).map(&:to_i)
  end

  # All group IDs reachable from this group via any edge type (nested or overlapping).
  # Unlike descendant_group_ids, this does NOT stop at overlapping links.
  # Used for circular-reference validation and UI exclusion lists.
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
  # Overlapping groups appear but their own children do not.
  # Inclusion overrides are applied during traversal.
  # children_map is built from reachable_group_ids so that overrides making a
  # "none" edge more permissive have the deeper descendants available for
  # navigation; the heavy preload (profiles + blobs) is limited to the groups
  # that are actually traversed.
  def descendant_sections
    all_ids = reachable_group_ids - [ id ]
    return [] if all_ids.empty?

    children_map = build_children_map([ id ] + all_ids)
    overrides_by_edge = build_overrides_by_edge(children_map)
    traversed_ids = collect_traversed_group_ids(children_map, overrides_by_edge)

    groups_by_id = Group.where(id: traversed_ids)
                        .includes(profiles: { avatar_attachment: :blob }, avatar_attachment: :blob)
                        .index_by(&:id)

    walk_descendants(id, children_map, groups_by_id, overrides_by_edge, {})
  end

  # Build a nested tree of all descendant groups for tree-view navigation.
  # Returns an array of nodes: { group:, profiles:, children:, overlapping: }
  # Overlapping groups appear in the tree but their own children are omitted.
  # Each profile entry is a hash { profile:, repeated: } so the view can
  # visually distinguish profiles that appear more than once in the tree.
  # Inclusion overrides are applied during traversal.
  # children_map is built from reachable_group_ids so that overrides making a
  # "none" edge more permissive have the deeper descendants available for
  # navigation; the heavy preload (profiles + blobs) is limited to the groups
  # that are actually traversed.
  def descendant_tree(seen_profile_ids: nil)
    all_ids = reachable_group_ids - [ id ]
    return [] if all_ids.empty?

    children_map = build_children_map([ id ] + all_ids)
    overrides_by_edge = build_overrides_by_edge(children_map)
    traversed_ids = collect_traversed_group_ids(children_map, overrides_by_edge)

    groups_by_id = Group.where(id: traversed_ids)
                        .includes(profiles: { avatar_attachment: :blob }, avatar_attachment: :blob)
                        .index_by(&:id)

    seen_profile_ids ||= Set.new
    build_tree(id, children_map, groups_by_id, seen_profile_ids, overrides_by_edge, {})
  end

  # Override-aware profile visibility from this group.
  # Self always includes all its own profiles. Returns a hash with:
  #   all_group_ids:        group IDs where all profiles are visible
  #   selected_profile_ids: individual profile IDs from "selected" mode groups
  # Uses reachable_group_ids for preloading so that overrides making a "none"
  # edge more permissive have the deeper descendants available in children_map.
  def profile_visibility
    desc_ids = reachable_group_ids - [ id ]
    all_groups = Set.new([ id ])
    selected_profiles = Set.new
    return { all_group_ids: all_groups.to_a, selected_profile_ids: selected_profiles.to_a } if desc_ids.empty?

    children_map = build_children_map([ id ] + desc_ids)
    overrides_by_edge = build_overrides_by_edge(children_map)

    collect_profile_visibility(id, children_map, all_groups, selected_profiles, overrides_by_edge, {})
    { all_group_ids: all_groups.to_a, selected_profile_ids: selected_profiles.to_a }
  end

  # Memoized variant for repeated reads during a single request
  # (e.g. sidebar panel partials rendered off the same loaded group).
  # Uses per-instance memoization rather than a cross-request cache so that
  # changes to edges / overrides are always reflected on the next request.
  def cached_profile_visibility
    @cached_profile_visibility ||= profile_visibility
  end

  # Collect all profiles from this group and all descendant groups,
  # respecting inclusion overrides and profile_inclusion_mode settings.
  # Profiles may appear in multiple sub-groups; the result is de-duplicated.
  def all_profiles
    vis = profile_visibility
    group_profile_ids = GroupProfile.where(group_id: vis[:all_group_ids]).select(:profile_id)

    if vis[:selected_profile_ids].any?
      Profile.where(id: group_profile_ids).or(Profile.where(id: vis[:selected_profile_ids]))
    else
      Profile.where(id: group_profile_ids)
    end
  end

  # Build a tree for the tree editor. Shows ALL physical edges unfiltered
  # (regardless of inclusion mode), with edge metadata and any overrides
  # for this group's direct edges. Used for the management UI where users
  # configure inclusion modes and overrides at every depth.
  def editor_tree
    all_ids = reachable_group_ids - [ id ]
    return [] if all_ids.empty?

    children_map = build_children_map([ id ] + all_ids)

    # Preload overrides for this group's direct child edges only
    direct_gg_ids = (children_map[id] || []).map { |e| e[:gg_id] }
    overrides_by_origin = {}
    if direct_gg_ids.any?
      InclusionOverride.where(group_group_id: direct_gg_ids).each do |ov|
        overrides_by_origin[ov.group_group_id] ||= {}
        overrides_by_origin[ov.group_group_id][ov.target_group_id] = ov
      end
    end

    groups_by_id = Group.where(id: all_ids)
                        .includes(avatar_attachment: :blob)
                        .index_by(&:id)

    # Preload profiles per group for the editor UI (needed for profile checkboxes)
    gp_data = GroupProfile.where(group_id: all_ids).pluck(:group_id, :profile_id)
    all_profile_ids = gp_data.map(&:last).uniq
    profiles_by_id = all_profile_ids.any? ? Profile.where(id: all_profile_ids).order(:name).index_by(&:id) : {}
    profiles_by_group = Hash.new { |h, k| h[k] = [] }
    gp_data.each do |gid, pid|
      profiles_by_group[gid] << profiles_by_id[pid] if profiles_by_id[pid]
    end
    profiles_by_group.each_value { |profs| profs.sort_by!(&:name) }
    groups_with_profiles = Set.new(profiles_by_group.keys)

    build_editor_nodes(id, children_map, groups_by_id, overrides_by_origin, nil, 0, [], groups_with_profiles, profiles_by_group)
  end

  private

  # Build the children_map used by tree traversal methods.
  # Includes the GroupGroup record id (gg_id) and profile inclusion settings
  # so that override logic can look up and apply per-edge overrides.
  # Returns { parent_group_id => [ { gg_id:, id:, subgroup_inclusion_mode:, included_subgroup_ids:, profile_inclusion_mode:, included_profile_ids: } ] }
  def build_children_map(parent_ids)
    GroupGroup.where(parent_group_id: parent_ids)
      .pluck(:id, :parent_group_id, :child_group_id, :subgroup_inclusion_mode, :included_subgroup_ids, :profile_inclusion_mode, :included_profile_ids)
      .group_by { |r| r[1] }
      .transform_values do |rows|
        rows.map { |r| { gg_id: r[0], id: r[2], subgroup_inclusion_mode: r[3], included_subgroup_ids: Array(r[4]).map(&:to_i), profile_inclusion_mode: r[5], included_profile_ids: Array(r[6]).map(&:to_i) } }
      end
  end

  # Preload inclusion overrides indexed by edge (group_group_id) then target_group_id.
  # Returns { gg_id => { target_group_id => { subgroup_inclusion_mode:, included_subgroup_ids:, profile_inclusion_mode:, included_profile_ids: } } }
  def build_overrides_by_edge(children_map)
    all_gg_ids = children_map.values.flatten.map { |e| e[:gg_id] }
    return {} if all_gg_ids.empty?

    InclusionOverride.where(group_group_id: all_gg_ids)
      .pluck(:group_group_id, :target_group_id, :subgroup_inclusion_mode, :included_subgroup_ids, :profile_inclusion_mode, :included_profile_ids)
      .group_by(&:first)
      .transform_values do |rows|
        rows.to_h { |r| [ r[1], { subgroup_inclusion_mode: r[2], included_subgroup_ids: Array(r[3]).map(&:to_i), profile_inclusion_mode: r[4], included_profile_ids: Array(r[5]).map(&:to_i) } ] }
      end
  end

  # -- Editor tree (manage_groups) ---------------------------------------------

  # Build the full unfiltered tree for the editor UI.
  # Unlike build_tree (which filters by inclusion mode), this follows ALL edges
  # so the user can see and configure every descendant.
  # Each node carries:
  #   group:, has_profiles:, profiles_list:, children:, depth:,
  #   gg_id:          — the GroupGroup id for this specific physical edge
  #   origin_gg_id:   — the root's direct edge that leads to this subtree
  #   edge_mode:, edge_included_ids:, edge_profile_mode:, edge_included_profile_ids: — the physical edge settings
  #   override:       — the InclusionOverride record (or nil) for depth 2+
  #   current_mode:, current_included_ids:, current_profile_mode:, current_included_profile_ids: — effective settings
  #   hidden_from_public: — true when this node won't appear in the public view
  #     (because a parent's mode excludes it, or an ancestor is already hidden)
  def build_editor_nodes(parent_id, children_map, groups_by_id, overrides_by_origin, origin_gg_id, depth, path, groups_with_profiles, profiles_by_group,
                         parent_mode: nil, parent_included_ids: nil, ancestor_hidden: false)
    (children_map[parent_id] || [])
      .filter_map { |entry| groups_by_id[entry[:id]] ? [ groups_by_id[entry[:id]], entry ] : nil }
      .reject { |_, entry| path.include?(entry[:id]) }
      .sort_by { |g, _| g.name }
      .map do |g, entry|
        current_origin = depth == 0 ? entry[:gg_id] : origin_gg_id
        override = depth > 0 ? overrides_by_origin.dig(current_origin, g.id) : nil

        eff_mode = override ? override.subgroup_inclusion_mode : entry[:subgroup_inclusion_mode]
        eff_included_ids = override ? Array(override.included_subgroup_ids).map(&:to_i) : entry[:included_subgroup_ids]
        eff_profile_mode = override ? override.profile_inclusion_mode : entry[:profile_inclusion_mode]
        eff_included_profile_ids = override ? Array(override.included_profile_ids).map(&:to_i) : entry[:included_profile_ids]

        hidden = node_hidden_from_public?(depth, ancestor_hidden, parent_mode, parent_included_ids, g.id)

        {
          group: g,
          has_profiles: groups_with_profiles.include?(g.id),
          profiles_list: profiles_by_group[g.id] || [],
          children: build_editor_nodes(
            g.id, children_map, groups_by_id, overrides_by_origin, current_origin, depth + 1, path + [ g.id ], groups_with_profiles, profiles_by_group,
            parent_mode: eff_mode, parent_included_ids: eff_included_ids, ancestor_hidden: hidden
          ),
          depth: depth + 1,
          gg_id: entry[:gg_id],
          origin_gg_id: current_origin,
          edge_mode: entry[:subgroup_inclusion_mode],
          edge_included_ids: entry[:included_subgroup_ids],
          edge_profile_mode: entry[:profile_inclusion_mode],
          edge_included_profile_ids: entry[:included_profile_ids],
          override: override,
          current_mode: eff_mode,
          current_included_ids: eff_included_ids,
          current_profile_mode: eff_profile_mode,
          current_included_profile_ids: eff_included_profile_ids,
          hidden_from_public: hidden
        }
      end
  end

  # Determine whether an editor-tree node is hidden from the public view.
  # Depth-0 nodes (direct children of the root) are always visible.
  # Deeper nodes are hidden when an ancestor is already hidden, or when the
  # parent's effective inclusion mode excludes this child.
  def node_hidden_from_public?(depth, ancestor_hidden, parent_mode, parent_included_ids, group_id)
    return false if depth == 0
    return true if ancestor_hidden
    return true if parent_mode == "none"
    return true if parent_mode == "selected" && !parent_included_ids&.include?(group_id)

    false
  end

  # Resolve effective settings for a child group entry, accounting for any
  # override targeting this group in the current traversal context.
  # Returns [subgroup_inclusion_mode, included_subgroup_ids, profile_inclusion_mode, included_profile_ids].
  def effective_settings(entry, overrides_map)
    override = overrides_map[entry[:id]]
    if override
      [ override[:subgroup_inclusion_mode], override[:included_subgroup_ids], override[:profile_inclusion_mode], override[:included_profile_ids] ]
    else
      [ entry[:subgroup_inclusion_mode], entry[:included_subgroup_ids], entry[:profile_inclusion_mode], entry[:included_profile_ids] ]
    end
  end

  # Merge an edge's overrides into the running overrides_map.
  # Later (closer) overrides take precedence over earlier (farther) ones.
  def merge_overrides(entry, overrides_by_edge, overrides_map)
    edge_ovs = overrides_by_edge[entry[:gg_id]]
    edge_ovs ? overrides_map.merge(edge_ovs) : overrides_map
  end

  # -- Flat descendant list (descendant_sections) ----------------------------

  def walk_descendants(parent_id, children_map, groups_by_id, overrides_by_edge, overrides_map)
    (children_map[parent_id] || [])
      .filter_map { |entry| groups_by_id[entry[:id]] ? [ groups_by_id[entry[:id]], entry ] : nil }
      .sort_by { |g, _| g.name }
      .flat_map do |g, entry|
        merged_map = merge_overrides(entry, overrides_by_edge, overrides_map)
        eff_mode, eff_subgroups, _eff_profile_mode, _eff_profile_ids = effective_settings(entry, merged_map)

        case eff_mode
        when "all"
          [ g, *walk_descendants(g.id, children_map, groups_by_id, overrides_by_edge, merged_map) ]
        when "selected"
          selected = walk_selected_descendants(g.id, eff_subgroups, children_map, groups_by_id, overrides_by_edge, merged_map)
          [ g, *selected ]
        else
          [ g ]
        end
      end
  end

  # Walk descendants for a "selected" edge — flat list for descendant_sections.
  # Mirrors build_selected_children but produces a flat depth-first array of groups.
  def walk_selected_descendants(parent_id, included_ids, children_map, groups_by_id, overrides_by_edge, overrides_map)
    (children_map[parent_id] || [])
      .select { |e| included_ids.include?(e[:id]) }
      .filter_map { |e| groups_by_id[e[:id]] ? [ groups_by_id[e[:id]], e ] : nil }
      .sort_by { |sg, _| sg.name }
      .flat_map do |sg, se|
        merged_map = merge_overrides(se, overrides_by_edge, overrides_map)
        eff_mode, eff_subgroups, _eff_profile_mode, _eff_profile_ids = effective_settings(se, merged_map)

        case eff_mode
        when "all"
          [ sg, *walk_descendants(sg.id, children_map, groups_by_id, overrides_by_edge, merged_map) ]
        when "selected"
          [ sg, *walk_selected_descendants(sg.id, eff_subgroups, children_map, groups_by_id, overrides_by_edge, merged_map) ]
        else
          [ sg ]
        end
      end
  end

  # -- Nested tree (descendant_tree) ----------------------------------------

  def build_tree(parent_id, children_map, groups_by_id, seen_profile_ids, overrides_by_edge, overrides_map)
    (children_map[parent_id] || [])
      .filter_map { |entry| groups_by_id[entry[:id]] ? [ groups_by_id[entry[:id]], entry ] : nil }
      .sort_by { |g, _| g.name }
      .map do |g, entry|
        merged_map = merge_overrides(entry, overrides_by_edge, overrides_map)
        eff_mode, eff_subgroups, eff_profile_mode, eff_profile_ids = effective_settings(entry, merged_map)

        overlapping = eff_mode == "none"
        children = case eff_mode
        when "all"
                     build_tree(g.id, children_map, groups_by_id, seen_profile_ids, overrides_by_edge, merged_map)
        when "selected"
                     build_selected_children(g.id, eff_subgroups, children_map, groups_by_id, seen_profile_ids, overrides_by_edge, merged_map)
        else
                     []
        end

        visible_profiles = filter_profiles_by_mode(g.profiles.to_a, eff_profile_mode, eff_profile_ids)

        {
          group: g,
          profiles: tag_profiles(visible_profiles, seen_profile_ids),
          children: children,
          overlapping: overlapping
        }
      end
  end

  # Build children for a "selected" edge — respects each sub-edge's own inclusion_mode
  # and any overrides in the current traversal context.
  def build_selected_children(parent_id, included_ids, children_map, groups_by_id, seen_profile_ids, overrides_by_edge, overrides_map)
    (children_map[parent_id] || [])
      .select { |e| included_ids.include?(e[:id]) }
      .filter_map do |e|
        child_group = groups_by_id[e[:id]]
        next unless child_group

        merged_map = merge_overrides(e, overrides_by_edge, overrides_map)
        eff_mode, eff_subgroups, eff_profile_mode, eff_profile_ids = effective_settings(e, merged_map)

        child_children = case eff_mode
        when "all"
                           build_tree(child_group.id, children_map, groups_by_id, seen_profile_ids, overrides_by_edge, merged_map)
        when "selected"
                           build_selected_children(child_group.id, eff_subgroups, children_map, groups_by_id, seen_profile_ids, overrides_by_edge, merged_map)
        else
                           []
        end

        visible_profiles = filter_profiles_by_mode(child_group.profiles.to_a, eff_profile_mode, eff_profile_ids)

        {
          group: child_group,
          profiles: tag_profiles(visible_profiles, seen_profile_ids),
          children: child_children,
          overlapping: eff_mode == "none"
        }
      end
  end

  # -- Profile visibility collection (for all_profiles) ----------------

  def collect_profile_visibility(parent_id, children_map, all_groups, selected_profiles, overrides_by_edge, overrides_map)
    (children_map[parent_id] || []).each do |entry|
      merged_map = merge_overrides(entry, overrides_by_edge, overrides_map)
      eff_mode, eff_subgroups, eff_profile_mode, eff_profile_ids = effective_settings(entry, merged_map)

      case eff_profile_mode
      when "all"
        all_groups.add(entry[:id])
      when "selected"
        eff_profile_ids.each { |pid| selected_profiles.add(pid) }
      end

      case eff_mode
      when "all"
        collect_profile_visibility(entry[:id], children_map, all_groups, selected_profiles, overrides_by_edge, merged_map)
      when "selected"
        collect_selected_profile_visibility(entry[:id], eff_subgroups, children_map, all_groups, selected_profiles, overrides_by_edge, merged_map)
      end
    end
  end

  def collect_selected_profile_visibility(parent_id, included_ids, children_map, all_groups, selected_profiles, overrides_by_edge, overrides_map)
    (children_map[parent_id] || [])
      .select { |e| included_ids.include?(e[:id]) }
      .each do |e|
        merged_map = merge_overrides(e, overrides_by_edge, overrides_map)
        eff_mode, eff_subgroups, eff_profile_mode, eff_profile_ids = effective_settings(e, merged_map)

        case eff_profile_mode
        when "all"
          all_groups.add(e[:id])
        when "selected"
          eff_profile_ids.each { |pid| selected_profiles.add(pid) }
        end

        case eff_mode
        when "all"
          collect_profile_visibility(e[:id], children_map, all_groups, selected_profiles, overrides_by_edge, merged_map)
        when "selected"
          collect_selected_profile_visibility(e[:id], eff_subgroups, children_map, all_groups, selected_profiles, overrides_by_edge, merged_map)
        end
      end
  end

  # -- Traversed group ID collection ----------------------------------------

  # Compute the set of descendant group IDs that will actually be visited
  # during traversal, respecting inclusion modes and overrides.
  # children_map and overrides_by_edge must already be built.
  def collect_traversed_group_ids(children_map, overrides_by_edge)
    result = Set.new
    collect_traversed_ids(id, children_map, overrides_by_edge, {}, result)
    result.to_a
  end

  def collect_traversed_ids(parent_id, children_map, overrides_by_edge, overrides_map, result)
    (children_map[parent_id] || []).each do |entry|
      merged_map = merge_overrides(entry, overrides_by_edge, overrides_map)
      eff_mode, eff_subgroups, _eff_profile_mode, _eff_profile_ids = effective_settings(entry, merged_map)
      result.add(entry[:id])

      case eff_mode
      when "all"
        collect_traversed_ids(entry[:id], children_map, overrides_by_edge, merged_map, result)
      when "selected"
        collect_selected_traversed_ids(entry[:id], eff_subgroups, children_map, overrides_by_edge, merged_map, result)
      end
    end
  end

  def collect_selected_traversed_ids(parent_id, included_ids, children_map, overrides_by_edge, overrides_map, result)
    (children_map[parent_id] || [])
      .select { |e| included_ids.include?(e[:id]) }
      .each do |e|
        merged_map = merge_overrides(e, overrides_by_edge, overrides_map)
        eff_mode, eff_subgroups, _eff_profile_mode, _eff_profile_ids = effective_settings(e, merged_map)
        result.add(e[:id])

        case eff_mode
        when "all"
          collect_traversed_ids(e[:id], children_map, overrides_by_edge, merged_map, result)
        when "selected"
          collect_selected_traversed_ids(e[:id], eff_subgroups, children_map, overrides_by_edge, merged_map, result)
        end
      end
  end

  # -- Shared helpers -------------------------------------------------------

  # Filter a group's profiles based on profile inclusion mode.
  # Returns the filtered array of profiles.
  def filter_profiles_by_mode(profiles, profile_mode, included_profile_ids)
    case profile_mode
    when "all"
      profiles
    when "selected"
      profiles.select { |p| included_profile_ids.include?(p.id) }
    else
      []
    end
  end

  # Tag each profile with :repeated based on whether it has been seen before.
  # Mutates seen_profile_ids in place so later nodes see earlier occurrences.
  def tag_profiles(profiles, seen_profile_ids)
    profiles.map do |profile|
      repeated = seen_profile_ids.include?(profile.id)
      seen_profile_ids.add(profile.id)
      { profile: profile, repeated: repeated }
    end
  end

  def generate_uuid
    self.uuid = PluralProfilesUuid.generate
  end
end
