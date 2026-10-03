# Custom ordering for groups and profiles. A list's order lives on whichever
# table defines membership of that list:
#
#   groups.position / profiles.position   the account-wide order
#   group_groups.position                 child groups inside a parent
#   group_profiles.position               profiles inside a group
#
# A NULL position means "not positioned": positioned items come first, then
# everything else alphabetically (see HasLabels). Lists nobody has reordered
# therefore stay alphabetical, and new members of a reordered list land at
# the end.
module Positioned
  extend ActiveSupport::Concern

  included do
    # Pass the link table's name to order by a position stored there, e.g.
    # group.profiles.order_by_position_then_name(:group_profiles).
    scope :order_by_position_then_name, ->(position_table = table_name) {
      order(Arel.sql("#{connection.quote_table_name(position_table)}.position ASC NULLS LAST"))
        .order_by_name_and_labels
    }
  end

  # In-memory equivalent of order_by_position_then_name, for trees built in
  # Ruby. Pass the link's position when ordering within a group.
  def position_sort_key(position = self.position)
    [ position.nil? ? 1 : 0, position || 0, *name_and_label_sort_key ]
  end
end
