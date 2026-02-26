class Group < ApplicationRecord
  include HasAvatar

  belongs_to :user
  has_many :group_profiles, dependent: :destroy
  has_many :profiles, -> { order(:name) }, through: :group_profiles

  has_many :parent_links, class_name: "GroupGroup", foreign_key: :child_group_id, dependent: :destroy
  has_many :child_links, class_name: "GroupGroup", foreign_key: :parent_group_id, dependent: :destroy
  has_many :parent_groups, through: :parent_links, source: :parent_group
  has_many :child_groups, through: :child_links, source: :child_group

  before_create :generate_uuid

  validates :name, presence: true
  validates :uuid, uniqueness: true

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
        UNION
        SELECT gg.child_group_id AS id,
               (gg.relationship_type = 'nested') AS recurse_further
        FROM group_groups gg
        INNER JOIN tree ON tree.id = gg.parent_group_id
        WHERE tree.recurse_further = true
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
  def descendant_sections
    desc_ids = descendant_group_ids - [ id ]
    return [] if desc_ids.empty?

    groups_by_id = Group.where(id: desc_ids)
                        .includes(profiles: { avatar_attachment: :blob }, avatar_attachment: :blob)
                        .index_by(&:id)

    children_map = GroupGroup.where(parent_group_id: [ id ] + desc_ids)
                             .pluck(:parent_group_id, :child_group_id, :relationship_type)
                             .group_by(&:first)
                             .transform_values { |rows| rows.map { |r| { id: r[1], relationship_type: r[2] } } }

    walk_descendants(id, children_map, groups_by_id)
  end

  # Build a nested tree of all descendant groups for tree-view navigation.
  # Returns an array of nodes: { group:, profiles:, children:, overlapping: }
  # Overlapping groups appear in the tree but their own children are omitted.
  def descendant_tree
    desc_ids = descendant_group_ids - [ id ]
    return [] if desc_ids.empty?

    groups_by_id = Group.where(id: desc_ids)
                        .includes(profiles: { avatar_attachment: :blob }, avatar_attachment: :blob)
                        .index_by(&:id)

    children_map = GroupGroup.where(parent_group_id: [ id ] + desc_ids)
                             .pluck(:parent_group_id, :child_group_id, :relationship_type)
                             .group_by(&:first)
                             .transform_values { |rows| rows.map { |r| { id: r[1], relationship_type: r[2] } } }

    build_tree(id, children_map, groups_by_id)
  end

  private

  def walk_descendants(parent_id, children_map, groups_by_id)
    (children_map[parent_id] || [])
      .filter_map { |entry| groups_by_id[entry[:id]] ? [ groups_by_id[entry[:id]], entry[:relationship_type] ] : nil }
      .sort_by { |g, _| g.name }
      .flat_map do |g, rel_type|
        if rel_type == "nested"
          [ g, *walk_descendants(g.id, children_map, groups_by_id) ]
        else
          [ g ]
        end
      end
  end

  def build_tree(parent_id, children_map, groups_by_id)
    (children_map[parent_id] || [])
      .filter_map { |entry| groups_by_id[entry[:id]] ? [ groups_by_id[entry[:id]], entry[:relationship_type] ] : nil }
      .sort_by { |g, _| g.name }
      .map do |g, rel_type|
        overlapping = rel_type == "overlapping"
        {
          group: g,
          profiles: g.profiles.to_a,
          children: overlapping ? [] : build_tree(g.id, children_map, groups_by_id),
          overlapping: overlapping
        }
      end
  end

  def generate_uuid
    self.uuid = SecureRandom.uuid
  end
end
