module SidebarTree
  extend ActiveSupport::Concern

  # Builds the full private sidebar tree data structure for this user.
  #
  # Returns a hash:
  #   {
  #     trees:        [ node, ... ],      # one node per top-level group
  #     all_profiles: ActiveRecord::Relation  # all profiles, in the account-wide custom order
  #   }
  #
  # Each node is a hash:
  #   {
  #     group:    <Group>,
  #     repeated: true/false,   # true if this group already appeared earlier in the traversal
  #     position: Integer/nil,  # its stored place in its list (see Positioned)
  #     profiles: [ { profile: <Profile>, repeated: true/false, position: Integer/nil }, ... ],
  #     children: [ ...child nodes... ]
  #   }
  #
  # Inclusion overrides are intentionally ignored — the private sidebar shows
  # everything for the account unconditionally.
  #
  # Ordering follows Positioned: top-level groups by the account-wide group
  # order, and everything inside a group by that group's own order.
  def sidebar_tree
    all_groups = groups.includes(
      avatar_attachment: :blob,
      group_profiles: { profile: { avatar_attachment: :blob } }
    )

    groups_by_id = all_groups.index_by(&:id)

    # Single query for all GroupGroup edges within this user's groups.
    # Used for both the child-ID set and the parent→children map.
    all_edges = GroupGroup.where(parent_group_id: groups.select(:id))
                          .pluck(:parent_group_id, :child_group_id, :position)

    all_child_ids = all_edges.map(&:second).to_set

    # Top-level groups: those that are not a child of any other group
    # belonging to this user.
    top_level = groups_by_id.values
                            .reject { |g| all_child_ids.include?(g.id) }
                            .sort_by(&:position_sort_key)

    # Build a global parent → [ [ child_id, position ], ... ] map for all of
    # this user's groups.
    children_map = all_edges.group_by(&:first)
                            .transform_values { |rows| rows.map { |_, child_id, position| [ child_id, position ] } }

    seen_profile_ids = Set.new
    seen_group_ids   = Set.new

    trees = top_level.map do |root|
      build_sidebar_node(root, root.position, children_map, groups_by_id, seen_profile_ids, seen_group_ids)
    end

    all_profiles = profiles.includes(avatar_attachment: :blob)
                            .order_by_position_then_name
                            .load

    { trees: trees, all_profiles: all_profiles }
  end

  private

  # Recursively builds a sidebar node for the given group. position is the
  # group's stored place in the list it's shown in.
  def build_sidebar_node(group, position, children_map, groups_by_id, seen_profile_ids, seen_group_ids)
    repeated = seen_group_ids.include?(group.id)
    seen_group_ids.add(group.id)

    link_positions = group.group_profiles.to_h { |link| [ link.profile_id, link.position ] }
    profile_entries = group.ordered_profiles_from_preload.map do |profile|
      entry = { profile: profile, repeated: seen_profile_ids.include?(profile.id), position: link_positions[profile.id] }
      seen_profile_ids.add(profile.id)
      entry
    end

    child_nodes = children_map.fetch(group.id, [])
                              .filter_map { |cid, child_position| [ groups_by_id[cid], child_position ] if groups_by_id[cid] }
                              .sort_by { |child, child_position| child.position_sort_key(child_position) }
                              .map do |child, child_position|
                                build_sidebar_node(child, child_position, children_map, groups_by_id, seen_profile_ids, seen_group_ids)
                              end

    { group: group, repeated: repeated, position: position, profiles: profile_entries, children: child_nodes }
  end
end
