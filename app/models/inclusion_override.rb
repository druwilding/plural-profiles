class InclusionOverride < ApplicationRecord
  belongs_to :group # the root group this override applies to

  validates :target_type, inclusion: { in: %w[Group Profile] }
  # NOTE: Cannot use the standard uniqueness validator here — ActiveRecord treats Array values as
  # IN (...) predicates, which breaks JSONB equality on the path column. The DB unique index
  # (idx_inclusion_overrides_unique) provides the hard constraint; this custom validation gives
  # a friendly error message at the model layer using an explicit JSONB cast.
  validate :path_not_nil
  validate :unique_within_path
  validate :same_user
  validate :path_groups_exist

  # Normalise path to an array of integers
  before_validation :normalise_path

  private

  def normalise_path
    self.path = Array(path).map(&:to_i)
  end

  def path_not_nil
    errors.add(:path, "can't be nil") if path.nil?
  end

  def unique_within_path
    return unless group_id && target_type && target_id && path

    scope = InclusionOverride
      .where(group_id: group_id, target_type: target_type, target_id: target_id)
      .where("path = ?::jsonb", path.to_json)
    scope = scope.where.not(id: id) if persisted?
    errors.add(:target_id, :taken) if scope.exists?
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
