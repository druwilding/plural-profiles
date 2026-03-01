class InclusionOverride < ApplicationRecord
  INCLUSION_MODES = %w[all selected none].freeze

  belongs_to :group_group
  belongs_to :target_group, class_name: "Group"

  validates :inclusion_mode, inclusion: { in: INCLUSION_MODES }
  validates :target_group_id, uniqueness: { scope: :group_group_id }
  validate :target_group_reachable

  private

  def target_group_reachable
    return unless group_group && target_group

    unless group_group.child_group.reachable_group_ids.include?(target_group_id)
      errors.add(:target_group, "is not reachable from the child group of this edge")
    end
  end
end
