require "test_helper"

class PurgeOrphanEmoteUploadsJobTest < ActiveJob::TestCase
  def blob(filename, metadata: { EmoteUpload::BLOB_METADATA_KEY => true }, created_at: 2.days.ago)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(png_bytes(8, 8)), filename: filename, metadata: metadata).tap do |blob|
      blob.update_column(:created_at, created_at)
    end
  end

  test "purges old, unattached emote uploads only" do
    orphan = blob("orphan.png")
    recent = blob("recent.png", created_at: 1.hour.ago)
    unrelated = blob("avatar.png", metadata: {})
    imported = blob("imported.png")
    emote = emotes(:red_heart)
    emote.image.attach(imported)

    PurgeOrphanEmoteUploadsJob.perform_now

    assert_not ActiveStorage::Blob.exists?(orphan.id)
    assert ActiveStorage::Blob.exists?(recent.id)
    assert ActiveStorage::Blob.exists?(unrelated.id)
    assert ActiveStorage::Blob.exists?(imported.id)
  end
end
