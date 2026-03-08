require "set"

class ReworkInclusionOverridesForCheckboxModel < ActiveRecord::Migration[8.1]
  def up
    # ── Phase 1: snapshot existing data before any schema changes ──────────
    edges_data = connection.exec_query(<<~SQL).to_a
      SELECT id, parent_group_id, child_group_id,
             subgroup_inclusion_mode, included_subgroup_ids,
             profile_inclusion_mode, included_profile_ids
      FROM group_groups
    SQL

    overrides_data = connection.exec_query(<<~SQL).to_a
      SELECT group_group_id, target_group_id,
             subgroup_inclusion_mode, included_subgroup_ids,
             profile_inclusion_mode, included_profile_ids
      FROM inclusion_overrides
    SQL

    profiles_data = connection.exec_query(<<~SQL).to_a
      SELECT group_id, profile_id FROM group_profiles
    SQL

    # ── Phase 2: clear old records & add new columns ──────────────────────
    execute "DELETE FROM inclusion_overrides"

    add_column :inclusion_overrides, :group_id, :bigint
    add_column :inclusion_overrides, :path, :jsonb, null: false, default: []
    add_column :inclusion_overrides, :target_type, :string
    add_column :inclusion_overrides, :target_id, :bigint

    # Relax old NOT-NULL constraints so new inserts (which leave old columns
    # NULL) don't fail while the old columns still exist.
    change_column_null :inclusion_overrides, :group_group_id, true
    change_column_null :inclusion_overrides, :target_group_id, true

    # ── Phase 3: migrate visibility state into new override records ───────
    migrate_visibility_data(edges_data, overrides_data, profiles_data)

    # ── Phase 4: drop old foreign keys, indexes, columns ─────────────────
    remove_foreign_key :inclusion_overrides, :group_groups
    remove_foreign_key :inclusion_overrides, column: :target_group_id

    remove_index :inclusion_overrides,
                 name: :idx_on_group_group_id_target_group_id_bb02b96ff7
    remove_index :inclusion_overrides,
                 name: :index_inclusion_overrides_on_group_group_id
    remove_index :inclusion_overrides,
                 name: :index_inclusion_overrides_on_target_group_id

    remove_column :inclusion_overrides, :group_group_id
    remove_column :inclusion_overrides, :target_group_id
    remove_column :inclusion_overrides, :subgroup_inclusion_mode
    remove_column :inclusion_overrides, :included_subgroup_ids
    remove_column :inclusion_overrides, :profile_inclusion_mode
    remove_column :inclusion_overrides, :included_profile_ids

    # ── Phase 5: enforce constraints on new columns ───────────────────────
    change_column_null :inclusion_overrides, :group_id, false
    change_column_null :inclusion_overrides, :target_type, false
    change_column_null :inclusion_overrides, :target_id, false

    add_index :inclusion_overrides,
              [ :group_id, :path, :target_type, :target_id ],
              unique: true,
              name: :idx_inclusion_overrides_unique

    add_index :inclusion_overrides, :group_id,
              name: :index_inclusion_overrides_on_group_id

    add_foreign_key :inclusion_overrides, :groups, on_delete: :cascade
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # ── Data migration ────────────────────────────────────────────────────────
  #
  # For every group that acts as a tree root (i.e. has at least one child
  # edge in group_groups), walk the tree using the OLD inclusion-mode /
  # override logic and create a new-style override record for every item
  # that would have been hidden from the public view.
  #
  # Path semantics (new model):
  #   path = array of group IDs from root (exclusive) to the group that
  #          *contains* the hidden target (inclusive).
  #          Empty array [] for items directly on the root.
  #
  # Example: Root A → B → C → profile P
  #   Hiding P: { group_id: A, path: [B, C], target_type: "Profile", target_id: P }
  #   Hiding C: { group_id: A, path: [B],    target_type: "Group",   target_id: C }
  # ──────────────────────────────────────────────────────────────────────────

  def migrate_visibility_data(edges_data, overrides_data, profiles_data)
    return if edges_data.empty?

    # Build lookup: parent_group_id → [ edge rows ]
    edges_by_parent = edges_data.group_by { |e| e["parent_group_id"] }

    # Build lookup: group_group_id → { target_group_id → override row }
    overrides_by_gg = {}
    overrides_data.each do |ov|
      gg_id = ov["group_group_id"]
      overrides_by_gg[gg_id] ||= {}
      overrides_by_gg[gg_id][ov["target_group_id"]] = ov
    end

    # Build lookup: group_id → [ profile_ids ]
    profiles_by_group = {}
    profiles_data.each do |gp|
      gid = gp["group_id"]
      profiles_by_group[gid] ||= []
      profiles_by_group[gid] << gp["profile_id"]
    end

    # De-duplicate: skip if the same (root, path, type, id) was already created
    created = Set.new

    # Every parent in group_groups is a potential root whose public tree
    # may contain hidden items.
    root_ids = edges_by_parent.keys
    root_ids.each do |root_id|
      walk_and_create_overrides(
        root_id: root_id,
        parent_id: root_id,
        path_to_parent: [],
        edges_by_parent: edges_by_parent,
        overrides_by_gg: overrides_by_gg,
        profiles_by_group: profiles_by_group,
        overrides_map: {},
        created: created
      )
    end
  end

  # Recursively walk the tree from +parent_id+, accumulating the traversal
  # path and the running overrides map. At each child group, determine the
  # effective inclusion settings (edge defaults merged with any overrides)
  # and create new-style override records for every hidden group or profile.
  #
  # Cycle prevention uses +path_to_parent+: if a child already appears in
  # the path we've walked, we skip it (mirrors the old editor_tree logic).
  def walk_and_create_overrides(root_id:, parent_id:, path_to_parent:,
                                edges_by_parent:, overrides_by_gg:,
                                profiles_by_group:, overrides_map:, created:)
    children = edges_by_parent[parent_id] || []

    children.each do |edge|
      child_id = edge["child_group_id"]
      gg_id    = edge["id"]

      # Cycle detection — same as the old editor_tree's `path.include?`
      next if path_to_parent.include?(child_id)

      # Merge overrides attached to this edge into the running map.
      # Later (closer) overrides win via Hash#merge, matching the old logic.
      merged_map = overrides_map.dup
      (overrides_by_gg[gg_id] || {}).each do |target_id, override_row|
        merged_map[target_id] = override_row
      end

      # Resolve effective settings for this child group.
      # An override targeting this child (from a parent edge) takes precedence
      # over the physical edge defaults.
      override_for_child = merged_map[child_id]
      if override_for_child
        eff_sub_mode    = override_for_child["subgroup_inclusion_mode"]
        eff_sub_ids     = parse_jsonb_ids(override_for_child["included_subgroup_ids"])
        eff_profile_mode = override_for_child["profile_inclusion_mode"]
        eff_profile_ids  = parse_jsonb_ids(override_for_child["included_profile_ids"])
      else
        eff_sub_mode    = edge["subgroup_inclusion_mode"]
        eff_sub_ids     = parse_jsonb_ids(edge["included_subgroup_ids"])
        eff_profile_mode = edge["profile_inclusion_mode"]
        eff_profile_ids  = parse_jsonb_ids(edge["included_profile_ids"])
      end

      # path_to_child is the path from root to this child group (inclusive).
      # Used as the `path` value for profile overrides (profiles live IN the child).
      # For group overrides targeting sub-groups, the container is the child,
      # so the path is also path_to_child.
      path_to_child = path_to_parent + [ child_id ]

      # ── Profile overrides ─────────────────────────────────────────────
      profiles = profiles_by_group[child_id] || []
      case eff_profile_mode
      when "none"
        profiles.each do |pid|
          insert_override(root_id, path_to_child, "Profile", pid, created)
        end
      when "selected"
        profiles.each do |pid|
          unless eff_profile_ids.include?(pid)
            insert_override(root_id, path_to_child, "Profile", pid, created)
          end
        end
      end
      # "all" → every profile visible, no overrides needed

      # ── Sub-group overrides ───────────────────────────────────────────
      grandchildren = edges_by_parent[child_id] || []

      case eff_sub_mode
      when "none"
        # All sub-groups of this child are hidden from the root's tree.
        grandchildren.each do |gc_edge|
          insert_override(root_id, path_to_child, "Group", gc_edge["child_group_id"], created)
        end
        # Still recurse into hidden sub-groups: they may have their own
        # non-"all" settings whose hidden items need explicit overrides,
        # so that unhiding a parent later doesn't accidentally reveal items
        # that were independently hidden at deeper levels.
        grandchildren.each do |gc_edge|
          gc_id = gc_edge["child_group_id"]
          next if path_to_child.include?(gc_id)
          walk_and_create_overrides(
            root_id: root_id,
            parent_id: gc_id,
            path_to_parent: path_to_child + [ gc_id ],
            edges_by_parent: edges_by_parent,
            overrides_by_gg: overrides_by_gg,
            profiles_by_group: profiles_by_group,
            overrides_map: merged_map,
            created: created
          )
        end

      when "selected"
        # Sub-groups NOT in the selected list are hidden.
        grandchildren.each do |gc_edge|
          gc_id = gc_edge["child_group_id"]
          unless eff_sub_ids.include?(gc_id)
            insert_override(root_id, path_to_child, "Group", gc_id, created)
          end
        end
        # Recurse into ALL sub-groups (visible and hidden) to capture
        # deeper-level settings.
        grandchildren.each do |gc_edge|
          gc_id = gc_edge["child_group_id"]
          next if path_to_child.include?(gc_id)
          walk_and_create_overrides(
            root_id: root_id,
            parent_id: gc_id,
            path_to_parent: path_to_child + [ gc_id ],
            edges_by_parent: edges_by_parent,
            overrides_by_gg: overrides_by_gg,
            profiles_by_group: profiles_by_group,
            overrides_map: merged_map,
            created: created
          )
        end

      when "all"
        # All sub-groups visible — recurse to check their settings.
        walk_and_create_overrides(
          root_id: root_id,
          parent_id: child_id,
          path_to_parent: path_to_child,
          edges_by_parent: edges_by_parent,
          overrides_by_gg: overrides_by_gg,
          profiles_by_group: profiles_by_group,
          overrides_map: merged_map,
          created: created
        )
      end
    end
  end

  # Insert a single new-style override record, skipping duplicates.
  def insert_override(root_id, path, target_type, target_id, created)
    key = [ root_id, path, target_type, target_id ]
    return if created.include?(key)
    created.add(key)

    execute ActiveRecord::Base.sanitize_sql([
      "INSERT INTO inclusion_overrides (group_id, path, target_type, target_id, created_at, updated_at) VALUES (?, ?::jsonb, ?, ?, NOW(), NOW())",
      root_id, path.to_json, target_type, target_id
    ])
  end

  # Parse a JSONB column value into an array of integer IDs.
  # Handles both pre-deserialised arrays and raw JSON strings.
  def parse_jsonb_ids(value)
    return [] if value.nil?
    ids = value.is_a?(String) ? JSON.parse(value) : Array(value)
    ids.map(&:to_i)
  end
end
