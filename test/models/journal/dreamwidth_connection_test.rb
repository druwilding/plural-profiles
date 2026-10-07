require "test_helper"

class Journal::DreamwidthConnectionTest < ActiveSupport::TestCase
  setup do
    @user = users(:three)
  end

  test "fixture keys are encrypted at rest and readable through the model" do
    connection = journal_dreamwidth_connections(:one_main)

    assert_equal "fakeKeyOneMain0001", connection.api_key
    stored = Journal::DreamwidthConnection.connection.select_value(
      "SELECT api_key FROM journal_dreamwidth_connections WHERE id = #{connection.id}"
    )
    assert_not_includes stored, "fakeKeyOneMain0001"
  end

  test "username is lowercased and hyphens become underscores" do
    connection = @user.dreamwidth_connections.create!(username: " My-Journal ", api_key: "key1")

    assert_equal "my_journal", connection.username
  end

  test "lookups by username are normalised the same way" do
    connection = @user.dreamwidth_connections.create!(username: "my_journal", api_key: "key1")

    assert_equal connection, @user.dreamwidth_connections.find_by(username: "My-Journal")
  end

  test "username must fit Dreamwidth's format" do
    [ "ab", "a" * 26, "has space", "dots.here" ].each do |username|
      connection = @user.dreamwidth_connections.build(username: username, api_key: "key1")

      assert_not connection.valid?, "#{username.inspect} should be invalid"
      assert connection.errors[:username].any?
    end
  end

  test "the same journal can't be connected twice by one person, in either spelling" do
    @user.dreamwidth_connections.create!(username: "my_journal", api_key: "key1")
    duplicate = @user.dreamwidth_connections.build(username: "My-Journal", api_key: "key2")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:username], "is already connected"
  end

  test "two people can connect the same journal" do
    shared = users(:three).dreamwidth_connections.build(username: "example_journal", api_key: "key3")

    assert shared.valid?
  end

  test "setting the key strips whitespace and sets an HMAC digest" do
    connection = @user.dreamwidth_connections.build(username: "my_journal", api_key: "  abc123\n")

    assert_equal "abc123", connection.api_key
    assert_equal Journal::DreamwidthConnection.digest_api_key("abc123"), connection.api_key_digest
    assert_not_equal Digest::SHA256.hexdigest("abc123"), connection.api_key_digest
  end

  test "a blank key is invalid and has no digest" do
    connection = @user.dreamwidth_connections.build(username: "my_journal", api_key: "   ")

    assert_nil connection.api_key_digest
    assert_not connection.valid?
    assert connection.errors[:api_key].any?
  end

  test "the same key can't be added twice by one person" do
    users(:one).dreamwidth_connections.build(username: "third_journal", api_key: "fakeKeyOneMain0001").tap do |duplicate|
      assert_not duplicate.valid?
      assert_includes duplicate.errors[:api_key_digest], "is already connected"
    end
  end

  test "an existing key can be found by its digest" do
    digest = Journal::DreamwidthConnection.digest_api_key("fakeKeyOneSecond0002")

    assert_equal journal_dreamwidth_connections(:one_second), users(:one).dreamwidth_connections.find_by(api_key_digest: digest)
  end

  test "api_key_last_four" do
    assert_equal "0001", journal_dreamwidth_connections(:one_main).api_key_last_four
  end

  test "record_failure! keeps the first failure time, and record_success! clears it" do
    connection = journal_dreamwidth_connections(:one_main)

    travel_to Time.zone.local(2026, 10, 7, 12, 0) do
      connection.record_failure!
    end
    travel_to Time.zone.local(2026, 10, 7, 13, 0) do
      connection.record_failure!
    end
    assert connection.failed?
    assert_equal Time.zone.local(2026, 10, 7, 12, 0), connection.reload.failed_at

    connection.record_success!
    assert_not connection.reload.failed?
  end

  test "connections go when their account does" do
    @user.dreamwidth_connections.create!(username: "my_journal", api_key: "key1")

    assert_difference -> { Journal::DreamwidthConnection.count }, -1 do
      @user.destroy!
    end
  end
end
