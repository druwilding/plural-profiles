require "test_helper"

class PluralProfilesUuidTest < ActiveSupport::TestCase
  test "returns a string in standard UUID format" do
    uuid = PluralProfilesUuid.generate
    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/, uuid)
  end

  test "never contains the digit 7" do
    1000.times do
      assert_no_match(/7/, PluralProfilesUuid.generate)
    end
  end

  test "generates unique values" do
    uuids = 100.times.map { PluralProfilesUuid.generate }
    assert_equal uuids.uniq.size, uuids.size
  end
end
