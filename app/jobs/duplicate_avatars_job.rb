class DuplicateAvatarsJob < ApplicationJob
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(duplication_task_id)
    task = DuplicationTask.find(duplication_task_id)
    task.update!(status: "in_progress")

    mappings = task.avatar_mappings

    copy_avatars(mappings["groups"], Group, task)
    copy_avatars(mappings["profiles"], Profile, task)

    task.update!(status: "completed")
  rescue StandardError => e
    task&.update(status: "failed") if task&.persisted?
    raise # Re-raise so Active Job's retry_on can handle it
  end

  private

  def copy_avatars(pairs, klass, task)
    return if pairs.blank?

    pairs.each do |source_id, target_id|
      source = klass.find_by(id: source_id)
      target = klass.find_by(id: target_id)
      next unless source && target && source.avatar.attached?

      begin
        source.avatar.blob.open do |tempfile|
          target.avatar.attach(
            io: tempfile,
            filename: source.avatar.blob.filename,
            content_type: source.avatar.blob.content_type
          )
        end
      rescue => e
        Rails.logger.warn "[DuplicateAvatarsJob] Failed to copy avatar " \
          "#{klass.name}##{source_id} → ##{target_id}: #{e.message}"
        next # Skip this avatar, continue with the rest
      end

      task.increment!(:copied_avatars)
    end
  end
end
