class Group < ApplicationRecord
  include HasAvatar

  belongs_to :user
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
    profiles.where.not(id: hidden_profile_ids).order(:name)
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
    profiles.includes(avatar_attachment: :blob).order(:name).map do |profile|
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
      .sort_by { |g, _| g.name }
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
      .sort_by { |g, _| g.name }
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

  # -- Management tree (management_tree) ------------------------------------

  def build_management_tree(parent_id, current_path, children_map, groups_by_id, overrides, ancestor_hidden)
    (children_map[parent_id] || [])
      .filter_map { |entry| groups_by_id[entry[:id]] ? [ groups_by_id[entry[:id]], entry ] : nil }
      .sort_by { |g, _| g.name }
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

  def generate_uuid
    self.uuid = PluralProfilesUuid.generate
  end
end
