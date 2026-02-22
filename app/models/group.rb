class Group < ApplicationRecord
  belongs_to :user
  has_many :group_profiles, dependent: :destroy
  has_many :profiles, through: :group_profiles

  has_many :parent_links, class_name: "GroupGroup", foreign_key: :child_group_id, dependent: :destroy
  has_many :child_links, class_name: "GroupGroup", foreign_key: :parent_group_id, dependent: :destroy
  has_many :parent_groups, through: :parent_links, source: :parent_group
  has_many :child_groups, through: :child_links, source: :child_group

  has_one_attached :avatar

  before_create :generate_uuid

  validates :name, presence: true
  validates :uuid, uniqueness: true

  def to_param
    uuid
  end

  # All group IDs in the descendant tree (this group + all children, recursive).
  # Uses a single recursive CTE query instead of N+1 queries per nesting level.
  def descendant_group_ids
    sql = <<~SQL.squish
      WITH RECURSIVE tree AS (
        SELECT CAST(:root_id AS bigint) AS id
        UNION
        SELECT gg.child_group_id AS id
        FROM group_groups gg
        INNER JOIN tree ON tree.id = gg.parent_group_id
      )
      SELECT id FROM tree
    SQL
    Group.connection.select_values(
      Group.sanitize_sql([ sql, root_id: id ])
    )
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
    )
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
  # Each group has its profiles eager-loaded.
  # Uses 3 queries total: CTE for IDs, groups with profiles, group_groups for tree structure.
  def descendant_sections
    desc_ids = descendant_group_ids - [ id ]
    return [] if desc_ids.empty?

    groups_by_id = Group.where(id: desc_ids)
                        .includes(:profiles)
                        .index_by(&:id)

    children_map = GroupGroup.where(parent_group_id: [ id ] + desc_ids)
                             .pluck(:parent_group_id, :child_group_id)
                             .group_by(&:first)
                             .transform_values { |pairs| pairs.map(&:last) }

    walk_descendants(id, children_map, groups_by_id)
  end

  # Build a nested tree of all descendant groups for tree-view navigation.
  # Returns an array of nodes: { group:, profiles:, children: [...] }
  # Each group has its profiles eager-loaded.
  def descendant_tree
    desc_ids = descendant_group_ids - [ id ]
    return [] if desc_ids.empty?

    groups_by_id = Group.where(id: desc_ids)
                        .includes(:profiles)
                        .index_by(&:id)

    children_map = GroupGroup.where(parent_group_id: [ id ] + desc_ids)
                             .pluck(:parent_group_id, :child_group_id)
                             .group_by(&:first)
                             .transform_values { |pairs| pairs.map(&:last) }

    build_tree(id, children_map, groups_by_id)
  end

  private

  def walk_descendants(parent_id, children_map, groups_by_id)
    (children_map[parent_id] || [])
      .filter_map { |cid| groups_by_id[cid] }
      .sort_by(&:name)
      .flat_map { |g| [ g, *walk_descendants(g.id, children_map, groups_by_id) ] }
  end

  def build_tree(parent_id, children_map, groups_by_id)
    (children_map[parent_id] || [])
      .filter_map { |cid| groups_by_id[cid] }
      .sort_by(&:name)
      .map do |g|
        {
          group: g,
          profiles: g.profiles.sort_by(&:name),
          children: build_tree(g.id, children_map, groups_by_id)
        }
      end
  end

  def generate_uuid
    self.uuid = SecureRandom.uuid
  end
end
