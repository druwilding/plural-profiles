# Purges emote uploads that were staged for review but never imported: blobs
# tagged by EmoteUpload that still aren't attached to anything a day later.
class PurgeOrphanEmoteUploadsJob < ApplicationJob
  def perform(older_than: 24.hours.ago)
    ActiveStorage::Blob
      .where.missing(:attachments)
      .where(created_at: ...older_than)
      .where("metadata::jsonb ->> ? = 'true'", EmoteUpload::BLOB_METADATA_KEY)
      .find_each(&:purge)
  end
end
