class InclusionOverride < ApplicationRecord
  belongs_to :group # the root group this override applies to

  validates :target_type, inclusion: { in: %w[Group Profile] }
  validates :target_id, uniqueness: { scope: %i[group_id path target_type] }
  validates :path, presence: true # [] is present; nil is not
  validate :same_user
  validate :path_groups_exist

  # Normalise path to an array of integers
  before_validation :normalise_path

  private

  def normalise_path
    self.path = Array(path).map(&:to_i)
  end

  def same_user
    return unless group

    target_record = target_type&.safe_constantize&.find_by(id: target_id)
    return unless target_record

    target_user_id = target_record.respond_to?(:user_id) ? target_record.user_id : nil
    errors.add(:target, "must belong to the same user") if target_user_id && target_user_id != group.user_id
  end

  def path_groups_exist
    return unless group && path.present? && path.any?

    reachable = group.reachable_group_ids
    path.each do |gid|
      unless reachable.include?(gid)
        errors.add(:path, "contains a group not in this tree")
        break
      end
    end
  end
end
