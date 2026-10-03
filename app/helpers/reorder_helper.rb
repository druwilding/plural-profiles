module ReorderHelper
  # Data attributes marking a sidebar item as reorderable by
  # sidebar_reorder_controller.js. list and group say which list the item
  # belongs to (see ListOrder); within names that list in announcements,
  # e.g. "Ash moved to position 2 of 3 in Household". position is its
  # stored place in that list, sent back with a save so the server can tell
  # whether another tab has reordered the list since.
  def reorder_item_data(record, list:, within:, position:, group: nil)
    {
      "reorder-item": "",
      "reorder-list": list,
      "reorder-group": group&.uuid,
      "reorder-id": record.uuid,
      "reorder-name": plain_field(record.name),
      "reorder-within": within,
      "reorder-position": position.to_s
    }.compact
  end
end
