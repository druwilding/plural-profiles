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

  private

  def generate_uuid
    self.uuid = SecureRandom.uuid
  end
end
