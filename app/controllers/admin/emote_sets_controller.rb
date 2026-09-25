# Adds, renames, reorders and deletes the site-wide emote sets shown as
# sections on the admin emotes page and in the pickers.
class Admin::EmoteSetsController < Admin::BaseController
  before_action :set_emote_set, except: %i[index create]

  def index
    @emote_sets = EmoteSet.site_wide.ordered.to_a
    @emote_counts = Emote.where(emote_set: @emote_sets).group(:emote_set_id).count
  end

  def create
    emote_set = EmoteSet.site_wide.new(emote_set_params)
    emote_set.position = (EmoteSet.site_wide.maximum(:position) || -1) + 1

    if emote_set.save
      redirect_to admin_emote_sets_path, notice: "Added the #{emote_set.name} set."
    else
      redirect_to admin_emote_sets_path, alert: "Couldn't add the set: #{emote_set.errors.full_messages.to_sentence}."
    end
  end

  def update
    if @emote_set.update(emote_set_params)
      redirect_to admin_emote_sets_path, notice: "Saved the #{@emote_set.name} set."
    else
      redirect_to admin_emote_sets_path, alert: "Couldn't save the set: #{@emote_set.errors.full_messages.to_sentence}."
    end
  end

  # Swaps the set with its neighbour, then renumbers every set so positions
  # stay 0, 1, 2… however they were before.
  def move
    emote_sets = EmoteSet.site_wide.ordered.to_a
    index = emote_sets.index(@emote_set)
    neighbour = params[:direction] == "up" ? index - 1 : index + 1

    if neighbour.between?(0, emote_sets.size - 1)
      emote_sets[index], emote_sets[neighbour] = emote_sets[neighbour], emote_sets[index]
      EmoteSet.transaction do
        emote_sets.each_with_index { |emote_set, position| emote_set.update!(position: position) }
      end
    end

    redirect_to admin_emote_sets_path
  end

  def destroy
    if @emote_set.destroy
      redirect_to admin_emote_sets_path, notice: "Deleted the #{@emote_set.name} set."
    else
      redirect_to admin_emote_sets_path, alert: "Only an empty set can be deleted. Move or delete its emotes first."
    end
  end

  private

  def set_emote_set
    @emote_set = EmoteSet.site_wide.find(params[:id])
  end

  def emote_set_params
    params.require(:emote_set).permit(:name)
  end
end
