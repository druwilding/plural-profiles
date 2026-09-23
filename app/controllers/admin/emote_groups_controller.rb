# Adds, renames, reorders and deletes the site-wide emote groups shown as
# sections on the admin emotes page and in the pickers.
class Admin::EmoteGroupsController < Admin::BaseController
  before_action :set_group, except: :create

  def create
    group = EmoteGroup.site_wide.new(group_params)
    group.position = (EmoteGroup.site_wide.maximum(:position) || -1) + 1

    if group.save
      redirect_to admin_emotes_path, notice: "Added the #{group.name} group."
    else
      redirect_to admin_emotes_path, alert: "Couldn't add the group: #{group.errors.full_messages.to_sentence}."
    end
  end

  def update
    if @group.update(group_params)
      redirect_to admin_emotes_path, notice: "Saved the #{@group.name} group."
    else
      redirect_to admin_emotes_path, alert: "Couldn't save the group: #{@group.errors.full_messages.to_sentence}."
    end
  end

  # Swaps the group with its neighbour, then renumbers every group so
  # positions stay 0, 1, 2… however they were before.
  def move
    groups = EmoteGroup.site_wide.ordered.to_a
    index = groups.index(@group)
    neighbour = params[:direction] == "up" ? index - 1 : index + 1

    if neighbour.between?(0, groups.size - 1)
      groups[index], groups[neighbour] = groups[neighbour], groups[index]
      EmoteGroup.transaction do
        groups.each_with_index { |group, position| group.update!(position: position) }
      end
    end

    redirect_to admin_emotes_path(anchor: "emote-groups")
  end

  def destroy
    if @group.destroy
      redirect_to admin_emotes_path, notice: "Deleted the #{@group.name} group."
    else
      redirect_to admin_emotes_path, alert: "Only an empty group can be deleted. Move or delete its emotes first."
    end
  end

  private

  def set_group
    @group = EmoteGroup.site_wide.find(params[:id])
  end

  def group_params
    params.require(:emote_group).permit(:name, :plain_text)
  end
end
