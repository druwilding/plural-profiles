# The admin page listing every site-wide emote by set, for quick renaming,
# moving between sets, overriding codes, removing old codes (aliases), and
# archiving, restoring or permanently deleting emotes.
#
# Every change re-renders the whole list (#emote-sections) with a Turbo Stream,
# so a renamed emote moves to its new sorted position. The preserve-focus
# controller puts focus back where the admin was.
class Admin::EmotesController < Admin::BaseController
  before_action :set_emote, except: %i[index upload upload_files resolve]

  def index
    load_sections
    @opened_emote_set_ids = Array(flash[:opened_emote_sets])
  end

  # Upload page: pick (or drop) files and the set they go into.
  def upload
    @emote_sets = site_emote_sets
  end

  # Imports every file it can straight away. Files whose name is already in
  # use (or that have no usable name) wait on a decision page instead.
  def upload_files
    if Array(params[:files]).none? { |file| file.respond_to?(:original_filename) }
      redirect_to upload_admin_emotes_path, alert: "Choose at least one image to upload."
      return
    end

    outcome = EmoteUpload.process(params[:files], emote_set_id: params[:emote_set_id])
    rejected = rejected_message(outcome.rejected)
    rejected = [ rejected, "Only the first #{EmoteUpload::MAX_FILES} files were uploaded." ].compact.join(" ") if outcome.truncated

    if outcome.pending.empty?
      flash[:alert] = rejected if rejected
      flash[:opened_emote_sets] = outcome.result.emote_set_ids
      redirect_to admin_emotes_path, notice: import_summary(outcome.result)
    else
      @rows = outcome.pending
      @summary = import_summary(outcome.result, none: nil)
      flash.now[:alert] = rejected if rejected
      render_decisions
    end
  end

  def resolve
    result, rows = EmoteUpload.resolve(params[:rows])
    if rows.empty?
      redirect_to upload_admin_emotes_path, alert: "Those files have expired. Try uploading them again."
    elsif result
      flash[:opened_emote_sets] = result.emote_set_ids
      redirect_to admin_emotes_path, notice: import_summary(result)
    else
      @rows = EmoteUpload.classify(rows)
      flash.now[:alert] = "Nothing was saved. Fix the files marked below, then save again."
      render_decisions(status: :unprocessable_content)
    end
  end

  def update
    if @emote.update(emote_params)
      respond_with_sections("Saved #{@emote.name}.")
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(helpers.dom_id(@emote),
            partial: "admin/emotes/emote", locals: { emote: @emote, emote_sets: site_emote_sets })
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
    params.require(:emote).permit(:name, :code, :code_overridden, :emote_set_id).tap do |permitted|
      if permitted.key?(:emote_set_id) && !site_emote_sets.map(&:id).include?(permitted[:emote_set_id].to_i)
        permitted.delete(:emote_set_id)
      end
      # The code box is disabled while the code is derived, so it isn't sent.
      permitted.delete(:code) if permitted[:code_overridden] == "0"
    end
  end

  def site_emotes
    Emote.joins(:emote_set).merge(EmoteSet.site_wide)
  end

  def site_emote_sets
    @site_emote_sets ||= EmoteSet.site_wide.ordered.to_a
  end

  def load_sections
    @emote_sets = site_emote_sets
    emotes = site_emotes.includes(:aliases, image_attachment: :blob).to_a
    archived, active = emotes.partition(&:archived?)
    @emotes_by_set = Emote.natural_sort(active).group_by(&:emote_set_id)
    @archived_emotes = Emote.natural_sort(archived)
  end

  def render_decisions(status: :ok)
    @emote_sets = site_emote_sets
    @taken_identifiers = EmoteUpload.taken_identifiers
    render :decide, status: status
  end

  def import_summary(result, none: "Nothing was imported.")
    parts = []
    parts << "#{pluralize_count(result.added, 'emote')} added" if result.added.positive?
    parts << "#{pluralize_count(result.replaced, 'image')} replaced" if result.replaced.positive?
    parts << "#{result.skipped} skipped" if result.skipped.positive?
    parts.any? ? "#{parts.to_sentence.upcase_first}." : none
  end

  def pluralize_count(count, noun)
    helpers.pluralize(count, noun)
  end

  def rejected_message(rows)
    return if rows.empty?
    "Not uploaded: " + rows.map { |row| "#{row.filename} #{row.error}" }.join("; ") + "."
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
