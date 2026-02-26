class GroupGroup < ApplicationRecord
  RELATIONSHIP_TYPES = %w[nested overlapping].freeze

  belongs_to :parent_group, class_name: "Group"
  belongs_to :child_group, class_name: "Group"

  validates :child_group_id, uniqueness: { scope: :parent_group_id }
  validates :relationship_type, inclusion: { in: RELATIONSHIP_TYPES }
  validate :same_user
  validate :not_self_referencing
  validate :no_circular_reference

  scope :nested, -> { where(relationship_type: "nested") }
  scope :overlapping, -> { where(relationship_type: "overlapping") }

  def nested?
    relationship_type == "nested"
  end

  def overlapping?
    relationship_type == "overlapping"
  end

  private

  def same_user
    return unless parent_group && child_group
    return if parent_group.user_id == child_group.user_id

    errors.add(:child_group, "must belong to the same user")
  end

  def not_self_referencing
    return unless parent_group_id == child_group_id

    errors.add(:child_group, "cannot be the same as the parent group")
  end

  def no_circular_reference
    return unless parent_group && child_group
    return if parent_group_id == child_group_id # already caught above

    if child_group.descendant_group_ids.include?(parent_group_id)
      errors.add(:child_group, "would create a circular reference")
    end
  end
end
