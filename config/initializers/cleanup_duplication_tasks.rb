# Delete finished DuplicationTask records that are more than 1 day old.
#
# Tasks are normally destroyed when the progress page redirects, but that step
# can be skipped when the job finishes before the page polls even once (the
# Stimulus controller redirects client-side via duplicate_status, never hitting
# duplicate_progress). This initializer is a safety net that runs at startup.
Rails.application.config.after_initialize do
  begin
    DuplicationTask
      .where(status: %w[completed failed])
      .where(updated_at: ..1.day.ago)
      .delete_all
  rescue => e
    Rails.logger.warn("[startup] DuplicationTask cleanup skipped: #{e.message}")
  end
end
