# Saves the custom order of one list of groups or profiles (see ListOrder).
# Called with fetch from the sidebar's reorder mode, so every response is
# just a status code: 204 when saved, 409 when the page's list is out of
# date, 404 for a group that isn't ours, 400 for an unknown list.
class Our::OrderingsController < ApplicationController
  def update
    group = Current.user.groups.find_by!(uuid: params[:group]) if params[:group].present?
    order = ListOrder.new(user: Current.user, list: params[:list].to_s, group: group)

    if params[:reset] == "true"
      order.reset!
    else
      order.save!(ordered_ids)
    end
    head :no_content
  rescue ListOrder::StaleList
    head :conflict
  rescue ListOrder::InvalidList
    head :bad_request
  end

  private

  # Anything but a plain list of strings can't match the list's members, so
  # it ends up as a 409 rather than an error.
  def ordered_ids
    ids = params[:ids]
    ids.is_a?(Array) ? ids.grep(String) : []
  end
end
