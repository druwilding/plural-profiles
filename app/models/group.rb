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
           (gg.inclusion_mode = 'all') AS recurse_further
        FROM group_groups gg
        INNER JOIN tree t ON t.id = gg.parent_group_id
        WHERE t.recurse_further = true
      )
      SELECT DISTINCT id FROM tree
      UNION
      SELECT DISTINCT (jsonb_array_elements_text(gg.included_subgroup_ids))::bigint AS id
      FROM group_groups gg
      INNER JOIN tree t ON t.id = gg.parent_group_id
      WHERE gg.inclusion_mode = 'selected' AND t.recurse_further = true
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

  # Collect all profiles from this group and all descendant groups.
  # Profiles may appear in multiple sub-groups; the result is de-duplicated.
  # Two queries total: one recursive CTE for group IDs, one for profiles.
  def all_profiles
    Profile.where(
      id: GroupProfile.where(group_id: descendant_group_ids).select(:profile_id)
    )
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
  def descendant_sections
    desc_ids = descendant_group_ids - [ id ]
    return [] if desc_ids.empty?

    groups_by_id = Group.where(id: desc_ids)
                        .includes(profiles: { avatar_attachment: :blob }, avatar_attachment: :blob)
                        .index_by(&:id)

    children_map = build_children_map([ id ] + desc_ids)
    overrides_by_edge = build_overrides_by_edge(children_map)

    walk_descendants(id, children_map, groups_by_id, overrides_by_edge, {})
  end

  # Build a nested tree of all descendant groups for tree-view navigation.
  # Returns an array of nodes: { group:, profiles:, children:, overlapping: }
  # Overlapping groups appear in the tree but their own children are omitted.
  # Each profile entry is a hash { profile:, repeated: } so the view can
  # visually distinguish profiles that appear more than once in the tree.
  # Inclusion overrides are applied during traversal.
  def descendant_tree(seen_profile_ids: nil)
    desc_ids = descendant_group_ids - [ id ]
    return [] if desc_ids.empty?

    groups_by_id = Group.where(id: desc_ids)
                        .includes(profiles: { avatar_attachment: :blob }, avatar_attachment: :blob)
                        .index_by(&:id)

    children_map = build_children_map([ id ] + desc_ids)
    overrides_by_edge = build_overrides_by_edge(children_map)

    seen_profile_ids ||= Set.new
    build_tree(id, children_map, groups_by_id, seen_profile_ids, overrides_by_edge, {})
  end

  # Override-aware set of group IDs whose profiles are visible from this group.
  # Self is always included. Uses Ruby tree traversal for precise results
  # (the CTE in descendant_group_ids is kept as a rough superset for preloading).
  def profile_visible_group_ids
    desc_ids = descendant_group_ids - [ id ]
    result = Set.new([ id ])
    return result.to_a if desc_ids.empty?

    children_map = build_children_map([ id ] + desc_ids)
    overrides_by_edge = build_overrides_by_edge(children_map)

    collect_profile_group_ids(id, children_map, result, overrides_by_edge, {})
    result.to_a
  end

  # Collect all profiles from this group and all descendant groups,
  # respecting inclusion overrides and include_direct_profiles flags.
  # Profiles may appear in multiple sub-groups; the result is de-duplicated.
  def all_profiles
    Profile.where(
      id: GroupProfile.where(group_id: profile_visible_group_ids).select(:profile_id)
    )
  end

  private

  # Build the children_map used by tree traversal methods.
  # Includes the GroupGroup record id (gg_id) and include_direct_profiles flag
  # so that override logic can look up and apply per-edge overrides.
  # Returns { parent_group_id => [ { gg_id:, id:, inclusion_mode:, included_subgroup_ids:, include_direct_profiles: } ] }
  def build_children_map(parent_ids)
    GroupGroup.where(parent_group_id: parent_ids)
      .pluck(:id, :parent_group_id, :child_group_id, :inclusion_mode, :included_subgroup_ids, :include_direct_profiles)
      .group_by { |r| r[1] }
      .transform_values do |rows|
        rows.map { |r| { gg_id: r[0], id: r[2], inclusion_mode: r[3], included_subgroup_ids: Array(r[4]).map(&:to_i), include_direct_profiles: r[5] } }
      end
  end

  # Preload inclusion overrides indexed by edge (group_group_id) then target_group_id.
  # Returns { gg_id => { target_group_id => { inclusion_mode:, included_subgroup_ids:, include_direct_profiles: } } }
  def build_overrides_by_edge(children_map)
    all_gg_ids = children_map.values.flatten.map { |e| e[:gg_id] }
    return {} if all_gg_ids.empty?

    InclusionOverride.where(group_group_id: all_gg_ids)
      .pluck(:group_group_id, :target_group_id, :inclusion_mode, :included_subgroup_ids, :include_direct_profiles)
      .group_by(&:first)
      .transform_values do |rows|
        rows.to_h { |r| [ r[1], { inclusion_mode: r[2], included_subgroup_ids: Array(r[3]).map(&:to_i), include_direct_profiles: r[4] } ] }
      end
  end

  # Resolve effective settings for a child group entry, accounting for any
  # override targeting this group in the current traversal context.
  # Returns [inclusion_mode, included_subgroup_ids, include_direct_profiles].
  def effective_settings(entry, overrides_map)
    override = overrides_map[entry[:id]]
    if override
      [ override[:inclusion_mode], override[:included_subgroup_ids], override[:include_direct_profiles] ]
    else
      [ entry[:inclusion_mode], entry[:included_subgroup_ids], entry[:include_direct_profiles] ]
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
        eff_mode, eff_subgroups, = effective_settings(entry, merged_map)

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
        eff_mode, eff_subgroups, = effective_settings(se, merged_map)

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
        eff_mode, eff_subgroups, eff_include_profiles = effective_settings(entry, merged_map)

        overlapping = eff_mode == "none"
        children = case eff_mode
        when "all"
                     build_tree(g.id, children_map, groups_by_id, seen_profile_ids, overrides_by_edge, merged_map)
        when "selected"
                     build_selected_children(g.id, eff_subgroups, children_map, groups_by_id, seen_profile_ids, overrides_by_edge, merged_map)
        else
                     []
        end

        {
          group: g,
          profiles: eff_include_profiles ? tag_profiles(g.profiles.to_a, seen_profile_ids) : [],
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
        eff_mode, eff_subgroups, eff_include_profiles = effective_settings(e, merged_map)

        child_children = case eff_mode
        when "all"
                           build_tree(child_group.id, children_map, groups_by_id, seen_profile_ids, overrides_by_edge, merged_map)
        when "selected"
                           build_selected_children(child_group.id, eff_subgroups, children_map, groups_by_id, seen_profile_ids, overrides_by_edge, merged_map)
        else
                           []
        end

        {
          group: child_group,
          profiles: eff_include_profiles ? tag_profiles(child_group.profiles.to_a, seen_profile_ids) : [],
          children: child_children,
          overlapping: eff_mode == "none"
        }
      end
  end

  # -- Profile-visible group ID collection (for all_profiles) ----------------

  def collect_profile_group_ids(parent_id, children_map, result, overrides_by_edge, overrides_map)
    (children_map[parent_id] || []).each do |entry|
      merged_map = merge_overrides(entry, overrides_by_edge, overrides_map)
      eff_mode, eff_subgroups, eff_include_profiles = effective_settings(entry, merged_map)

      result.add(entry[:id]) if eff_include_profiles

      case eff_mode
      when "all"
        collect_profile_group_ids(entry[:id], children_map, result, overrides_by_edge, merged_map)
      when "selected"
        collect_selected_profile_group_ids(entry[:id], eff_subgroups, children_map, result, overrides_by_edge, merged_map)
      end
    end
  end

  def collect_selected_profile_group_ids(parent_id, included_ids, children_map, result, overrides_by_edge, overrides_map)
    (children_map[parent_id] || [])
      .select { |e| included_ids.include?(e[:id]) }
      .each do |e|
        merged_map = merge_overrides(e, overrides_by_edge, overrides_map)
        eff_mode, eff_subgroups, eff_include_profiles = effective_settings(e, merged_map)

        result.add(e[:id]) if eff_include_profiles

        case eff_mode
        when "all"
          collect_profile_group_ids(e[:id], children_map, result, overrides_by_edge, merged_map)
        when "selected"
          collect_selected_profile_group_ids(e[:id], eff_subgroups, children_map, result, overrides_by_edge, merged_map)
        end
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

  def generate_uuid
    self.uuid = PluralProfilesUuid.generate
  end
end
