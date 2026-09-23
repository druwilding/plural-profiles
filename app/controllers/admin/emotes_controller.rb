# The admin page listing every site-wide emote by group, for quick renaming,
# moving between groups, overriding codes, removing old codes (aliases), and
# archiving, restoring or permanently deleting emotes.
#
# Every change re-renders the whole list (#emote-sections) with a Turbo Stream,
# so a renamed emote moves to its new sorted position. The preserve-focus
# controller puts focus back where the admin was.
class Admin::EmotesController < Admin::BaseController
  before_action :set_emote, except: :index

  def index
    load_sections
  end

  def update
    if @emote.update(emote_params)
      respond_with_sections("Saved #{@emote.name}.")
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(helpers.dom_id(@emote),
            partial: "admin/emotes/emote", locals: { emote: @emote, groups: site_groups })
        end
        format.html { redirect_to admin_emotes_path, alert: @emote.errors.full_messages.to_sentence }
      end
    end
  end

  def archive
    @emote.archive!
    respond_with_sections("Archived #{@emote.name}. It no longer appears in pickers, but still shows wherever it's already used.")
  end

  def restore
    @emote.restore!
    respond_with_sections("Restored #{@emote.name}.")
  end

  def remove_alias
    emote_alias = @emote.aliases.find(params[:alias_id])
    emote_alias.destroy!
    respond_with_sections("Removed the old code :#{emote_alias.code}: from #{@emote.name}.")
  end

  # Only archived emotes can be deleted, so deleting is always a deliberate
  # second step.
  def destroy
    unless @emote.archived?
      redirect_to admin_emotes_path, alert: "Archive #{@emote.name} before deleting it."
      return
    end

    @emote.destroy!
    respond_with_sections("Deleted #{@emote.name}.")
  end

  private

  def set_emote
    @emote = site_emotes.find(params[:id])
  end

  def emote_params
    params.require(:emote).permit(:name, :code, :code_overridden, :emote_group_id).tap do |permitted|
      if permitted.key?(:emote_group_id) && !site_groups.map(&:id).include?(permitted[:emote_group_id].to_i)
        permitted.delete(:emote_group_id)
      end
      # The code box is disabled while the code is derived, so it isn't sent.
      permitted.delete(:code) if permitted[:code_overridden] == "0"
    end
  end

  def site_emotes
    Emote.joins(:emote_group).merge(EmoteGroup.site_wide)
  end

  def site_groups
    @site_groups ||= EmoteGroup.site_wide.ordered.to_a
  end

  def load_sections
    @groups = site_groups
    emotes = site_emotes.includes(:aliases, image_attachment: :blob).to_a
    archived, active = emotes.partition(&:archived?)
    @emotes_by_group = Emote.natural_sort(active).group_by(&:emote_group_id)
    @archived_emotes = Emote.natural_sort(archived)
  end

  def respond_with_sections(status)
    respond_to do |format|
      format.turbo_stream do
        load_sections
        render turbo_stream: [
          turbo_stream.replace("emote-sections", partial: "admin/emotes/sections"),
          turbo_stream.update("emote-status", status)
        ]
      end
      format.html { redirect_to admin_emotes_path, notice: status }
    end
  end
end
