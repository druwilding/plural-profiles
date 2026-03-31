module SidebarTree
  extend ActiveSupport::Concern

  # Builds the full private sidebar tree data structure for this user.
  #
  # Returns a hash:
  #   {
  #     trees:           [ node, ... ],      # one node per top-level group
  #     orphan_profiles: ActiveRecord::Relation  # profiles not in any group
  #   }
  #
  # Each node is a hash:
  #   {
  #     group:    <Group>,
  #     repeated: true/false,   # true if this group already appeared earlier in the traversal
  #     profiles: [ { profile: <Profile>, repeated: true/false }, ... ],
  #     children: [ ...child nodes... ]
  #   }
  #
  # Inclusion overrides are intentionally ignored — the private sidebar shows
  # everything for the account unconditionally.
  def sidebar_tree
    all_groups = groups.includes(
      :profiles,
      :parent_links,
      avatar_attachment: :blob,
      profiles: { avatar_attachment: :blob }
    )

    groups_by_id = all_groups.index_by(&:id)

    # Single query for all GroupGroup edges within this user's groups.
    # Used for both the child-ID set and the parent→children map.
    all_edges = GroupGroup.where(parent_group_id: groups.select(:id))
                          .pluck(:parent_group_id, :child_group_id)

    all_child_ids = all_edges.map(&:last).to_set

    # Top-level groups: those that are not a child of any other group
    # belonging to this user.
    top_level = groups_by_id.values
                            .reject { |g| all_child_ids.include?(g.id) }
                            .sort_by(&:name_and_label_sort_key)

    # Build a global parent → children map for all of this user's groups.
    children_map = all_edges.group_by(&:first)
                            .transform_values { |rows| rows.map(&:last) }

    seen_profile_ids = Set.new
    seen_group_ids   = Set.new

    trees = top_level.map do |root|
      build_sidebar_node(root, children_map, groups_by_id, seen_profile_ids, seen_group_ids)
    end

    # Orphaned profiles: profiles not belonging to any group in this account.
    grouped_profile_ids = GroupProfile.where(group_id: groups.select(:id))
                                      .pluck(:profile_id).to_set

    orphans = profiles.includes(avatar_attachment: :blob)
                      .where.not(id: grouped_profile_ids)
                      .order_by_name_and_labels
                      .load

    { trees: trees, orphan_profiles: orphans }
  end

  private

  # Recursively builds a sidebar node for the given group.
  def build_sidebar_node(group, children_map, groups_by_id, seen_profile_ids, seen_group_ids)
    repeated = seen_group_ids.include?(group.id)
    seen_group_ids.add(group.id)

    profile_entries = group.profiles.sort_by(&:name_and_label_sort_key).map do |profile|
      entry = { profile: profile, repeated: seen_profile_ids.include?(profile.id) }
      seen_profile_ids.add(profile.id)
      entry
    end

    child_ids     = children_map.fetch(group.id, [])
    child_groups  = child_ids.filter_map { |cid| groups_by_id[cid] }
                             .sort_by(&:name_and_label_sort_key)

    child_nodes = child_groups.map do |child|
      build_sidebar_node(child, children_map, groups_by_id, seen_profile_ids, seen_group_ids)
    end

    { group: group, repeated: repeated, profiles: profile_entries, children: child_nodes }
  end
end
