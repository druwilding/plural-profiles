require "test_helper"

class Journal::EntryFormTest < ActiveSupport::TestCase
  def form(**attrs)
    Journal::EntryForm.new({ body: "Hello", datetime: "2026-10-08T14:05", datetime_original: "2026-10-08T14:05" }.merge(attrs))
  end

  test "needs some entry text" do
    entry = form(body: "  ")

    assert_not entry.valid?
    assert_includes entry.errors.full_messages, "Entry text can't be empty"
  end

  test "tags are split on commas, trimmed, and repeats dropped" do
    assert_equal [ "*mood", "fan art", "monday" ], form(tags: " *mood, fan art,,monday , fan art ").tag_list
  end

  test "a tag over 40 characters is refused, naming it" do
    long = "a" * 41
    entry = form(tags: "fine, #{long}")

    assert_not entry.valid?
    assert entry.errors[:tags].first.include?(long)
  end

  test "a 40 character tag is fine" do
    assert form(tags: "a" * 40).valid?
  end

  test "to_api sends what Dreamwidth takes, leaving out what's blank" do
    api = form(subject: "", tags: "one, two", icon: "").to_api

    assert_equal({ text: "Hello", security: "private", tags: [ "one", "two" ] }, api)
  end

  test "an unchanged date isn't sent, so Dreamwidth uses its own now" do
    assert_not form.to_api.key?(:datetime)
  end

  test "a changed date is sent in Dreamwidth's format" do
    assert_equal "2026-10-01 09:30", form(datetime: "2026-10-01T09:30").to_api[:datetime]
  end

  test "a date that isn't real is refused" do
    entry = form(datetime: nil)

    assert_not entry.valid?
    assert_includes entry.errors.full_messages, "Date isn't a real date"
  end

  test "in private-only mode, only private is allowed" do
    skip "private-only mode is off" unless Journal::PRIVATE_ONLY

    assert_not form(security: "public").valid?
    assert form(security: "private").valid?
  end

  test "the icon keyword is sent when one is chosen" do
    assert_equal "bass", form(icon: "bass").to_api[:icon]
  end
end
