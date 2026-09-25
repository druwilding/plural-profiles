require "test_helper"

class EmoteUploadTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  SVG = %(<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><rect width="8" height="8"/></svg>).freeze

  def upload(filename, bytes = png_bytes(8, 8), content_type = "image/png")
    Rack::Test::UploadedFile.new(StringIO.new(bytes), content_type, original_filename: filename)
  end

  def webp_bytes
    Vips::Image.black(8, 8).write_to_buffer(".webp")
  end

  def process_files(*files)
    EmoteUpload.process(files, group_id: emote_groups(:hearts).id)
  end

  def decision(row, **overrides)
    { signed_id: row.signed_id, name: row.name, group_id: row.group_id, action: row.action, replace_id: row.clash&.id }.merge(overrides)
  end

  # -- process --

  test "new files are imported straight away, named from the filename" do
    outcome = process_files(upload("07 Party.png"), upload("100.webp", webp_bytes, "image/webp"))

    assert_equal EmoteUpload::Result.new(added: 2, replaced: 0, skipped: 0, group_ids: [ emote_groups(:hearts).id ]), outcome.result
    assert_empty outcome.pending
    party = Emote.find_by!(name: "07-party")
    assert_equal "party", party.code
    assert_equal emote_groups(:hearts), party.emote_group
    assert_equal "image/webp", Emote.find_by!(name: "100").image.content_type
  end

  test "a file whose name, code or old code is in use waits for a decision, defaulting to replacing that emote's image" do
    emotes(:cadbury_heart).update!(name: "48-chocolate-heart")
    outcome = process_files(upload("07-party.png"), upload("36-red-heart.png"), upload("spring-heart.png"), upload("cadbury-heart.png"))

    assert_equal 1, outcome.result.added
    assert_equal %w[clash clash clash], outcome.pending.map(&:status)
    assert_equal [ emotes(:red_heart), emotes(:spring_heart), emotes(:cadbury_heart) ], outcome.pending.map(&:clash)
    assert_equal %w[replace replace replace], outcome.pending.map(&:action)
    assert outcome.pending.all? { |row| row.blob.attachments.none? }
  end

  test "two files with the same name: the first is added, the second waits, defaulting to skip" do
    outcome = process_files(upload("07-party.png"), upload("08-party.png"))

    assert_equal 1, outcome.result.added
    assert_equal [ "08-party" ], outcome.pending.map(&:name)
    assert_equal Emote.find_by!(name: "07-party"), outcome.pending.first.clash
    assert_equal "skip", outcome.pending.first.action
  end

  test "a file with no usable name waits for one" do
    outcome = process_files(upload("♥♥♥.png"))

    assert_equal 0, outcome.result.added
    assert_equal [ "unnamed" ], outcome.pending.map(&:status)
  end

  test "an SVG is rejected with a hint about the browser conversion, and never stored" do
    assert_no_difference -> { ActiveStorage::Blob.count } do
      row = process_files(upload("logo.svg", SVG, "image/svg+xml")).rejected.first
      assert_match "SVG that wasn't converted to PNG", row.error
    end
  end

  test "an SVG disguised as a PNG is still rejected" do
    assert_match "SVG", process_files(upload("logo.png", SVG, "image/png")).rejected.first.error
  end

  test "a file that isn't an image is rejected" do
    assert_equal "isn't a PNG or WebP image", process_files(upload("notes.txt", "hello", "text/plain")).rejected.first.error
  end

  test "a PNG that can't be decoded is rejected and its blob purged" do
    corrupt = png_bytes(8, 8).byteslice(0, 40)
    assert_no_difference -> { ActiveStorage::Blob.count } do
      assert_equal "couldn't be read as an image", process_files(upload("broken.png", corrupt)).rejected.first.error
    end
  end

  test "a file over the size limit is rejected" do
    big = upload("big.png")
    big.define_singleton_method(:size) { EmoteUpload::MAX_FILE_SIZE + 1 }

    assert_equal "is larger than 2 MB", process_files(big).rejected.first.error
  end

  test "only the first MAX_FILES files are used" do
    stub_const(EmoteUpload, :MAX_FILES, 2) do
      outcome = EmoteUpload.process([ upload("a.png"), upload("b.png"), upload("c.png") ], group_id: nil)
      assert_equal 2, outcome.result.added
      assert outcome.truncated
      assert_not Emote.exists?(name: "c")
    end
  end

  # -- resolve --

  test "replacing a clashing emote's image" do
    row = process_files(upload("36-red-heart.png")).pending.first
    old_blob = emotes(:red_heart).image.blob

    result, = EmoteUpload.resolve([ decision(row) ])

    assert_equal EmoteUpload::Result.new(added: 0, replaced: 1, skipped: 0, group_ids: [ emote_groups(:hearts).id ]), result
    assert_equal row.blob, emotes(:red_heart).reload.image.blob
    assert_not_equal old_blob, emotes(:red_heart).image.blob
  end

  test "adding a clash as a new emote under a new name" do
    row = process_files(upload("36-red-heart.png")).pending.first
    result, = EmoteUpload.resolve({ "0" => decision(row, name: "37-rouge-heart", action: "create") })

    assert_equal 1, result.added
    assert Emote.exists?(code: "rouge-heart")
  end

  test "if any decision fails, nothing is saved and the row has errors" do
    pending = process_files(upload("36-red-heart.png"), upload("spring-heart.png")).pending
    result, rows = EmoteUpload.resolve([ decision(pending.first), decision(pending.second, action: "create") ])

    assert_nil result
    assert_not_equal pending.first.blob, emotes(:red_heart).reload.image.blob
    assert_includes rows.second.errors_list, "Code “spring-heart” is already used by 02-spring-heart"
  end

  test "skipped files are purged" do
    row = process_files(upload("36-red-heart.png")).pending.first

    assert_enqueued_with(job: ActiveStorage::PurgeJob) do
      result, = EmoteUpload.resolve([ decision(row, action: "skip") ])
      assert_equal 1, result.skipped
    end
  end

  test "decisions for blobs that weren't emote uploads, or with unknown actions, are ignored or skipped" do
    other_blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(png_bytes(8, 8)), filename: "other.png")
    row = process_files(upload("36-red-heart.png")).pending.first

    rows = EmoteUpload.rows_from_params([
      { signed_id: other_blob.signed_id, name: "sneaky", action: "create" },
      { signed_id: "tampered", name: "sneaky", action: "create" },
      decision(row, action: "destroy_everything")
    ])

    assert_equal [ "36-red-heart" ], rows.map(&:name)
    assert_equal "skip", rows.first.action
  end

  test "names typed on the decision page are normalised like emote names, so clashes are still found" do
    row = process_files(upload("36-red-heart.png")).pending.first

    rows = EmoteUpload.classify(EmoteUpload.rows_from_params([ decision(row, name: " 36_Red_Heart ", action: nil) ]))

    assert_equal "36-red-heart", rows.first.name
    assert_equal "clash", rows.first.status
    assert_equal emotes(:red_heart), rows.first.clash
  end

  private

  def stub_const(klass, name, value)
    original = klass.const_get(name)
    klass.send(:remove_const, name)
    klass.const_set(name, value)
    yield
  ensure
    klass.send(:remove_const, name)
    klass.const_set(name, original)
  end
end
