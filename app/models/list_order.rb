# Saves the custom order of one list of groups or profiles (see Positioned).
#
# Lists:
#   "groups"          the user's top-level groups (the account-wide group order)
#   "profiles"        all of the user's profiles (the account-wide profile order)
#   "group_groups"    the child groups inside one group
#   "group_profiles"  the profiles inside one group
#
# Items are identified by their UUIDs. A save must name exactly the list's
# current members, so a stale page (from another tab, or from before a
# membership change) can't half-apply an order: it raises StaleList instead.
class ListOrder
  LISTS = %w[groups profiles group_groups group_profiles].freeze

  class StaleList < StandardError; end
  class InvalidList < ArgumentError; end

  def initialize(user:, list:, group: nil)
    raise InvalidList, "unknown list #{list.inspect}" unless LISTS.include?(list)
    raise InvalidList, "#{list} needs a group" if list.start_with?("group_") && group.nil?
    raise InvalidList, "group belongs to another user" if group && group.user_id != user.id

    @user = user
    @list = list
    @group = group
  end

  # Positions the list's members 0..n-1 in the given order.
  def save!(uuids)
    uuids = Array(uuids).map(&:to_s)

    ActiveRecord::Base.transaction do
      # Locks only the rows being written, not the groups or profiles joined in
      ids_by_uuid = members.lock("FOR UPDATE OF #{rows.quoted_table_name}").pluck(member_uuid_column, "#{rows.quoted_table_name}.id").to_h
      raise StaleList unless uuids.size == ids_by_uuid.size && uuids.to_set == ids_by_uuid.keys.to_set

      write_positions(uuids.map { |uuid| ids_by_uuid.fetch(uuid) })
      clear_positions_outside_list if @list == "groups"
    end
  end

  # Clears the list's positions, so it falls back to alphabetical order.
  def reset!
    ActiveRecord::Base.transaction do
      rows.update_all(position: nil)
      clear_positions_outside_list if @list == "groups"
    end
  end

  private

  # The rows whose position column orders this list: the groups or profiles
  # themselves for account-wide lists, the links for lists inside a group.
  def rows
    case @list
    when "groups"         then top_level_groups
    when "profiles"       then @user.profiles
    when "group_groups"   then GroupGroup.where(parent_group_id: @group.id)
    when "group_profiles" then GroupProfile.where(group_id: @group.id)
    end
  end

  # rows, joined to the item each row stands for so it can be found by UUID.
  def members
    case @list
    when "group_groups"   then rows.joins(:child_group)
    when "group_profiles" then rows.joins(:profile)
    else rows
    end
  end

  def member_uuid_column
    case @list
    when "group_groups"   then "groups.uuid"
    when "group_profiles" then "profiles.uuid"
    else "#{rows.table_name}.uuid"
    end
  end

  # The account-wide group order is set from the sidebar, which lists only
  # top-level groups.
  def top_level_groups
    nested_ids = GroupGroup.where(parent_group_id: @user.groups.select(:id)).select(:child_group_id)
    @user.groups.where.not(id: nested_ids)
  end

  # Groups that aren't top-level any more could still hold a position from
  # when they were. Clearing it keeps them from jumping ahead of other
  # nested groups in account-wide lists, like the chat pickers.
  def clear_positions_outside_list
    @user.groups.where.not(id: top_level_groups.select(:id)).where.not(position: nil).update_all(position: nil)
  end

  # One UPDATE for the whole list, however long it is.
  def write_positions(ids)
    return if ids.empty?

    model = rows.model
    position = Arel::Nodes::Case.new(model.arel_table[:id])
    ids.each_with_index { |id, index| position.when(id).then(index) }
    model.where(id: ids).update_all(position: position)
  end
end
