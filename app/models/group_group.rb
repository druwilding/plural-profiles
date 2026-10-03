class GroupGroup < ApplicationRecord
  belongs_to :parent_group, class_name: "Group"
  belongs_to :child_group, class_name: "Group"

  validates :child_group_id, uniqueness: { scope: :parent_group_id }
  validate :same_user
  validate :not_self_referencing
  validate :no_circular_reference

  after_create :clear_child_top_level_position

  private

  # groups.position is the order among top-level groups (see ListOrder), so
  # a group that's just been nested doesn't keep its old place there.
  def clear_child_top_level_position
    # In SQL, as the position may have been set since child_group was loaded
    Group.where(id: child_group_id).where.not(position: nil).update_all(position: nil)
  end

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

    if child_group.reachable_group_ids.include?(parent_group_id)
      errors.add(:child_group, "would create a circular reference")
    end
  end
end
