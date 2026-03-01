require "test_helper"

class InviteCodeTest < ActiveSupport::TestCase
  test "generates code on create" do
    code = users(:one).invite_codes.create!
    assert code.code.present?
    assert_equal InviteCode::CODE_LENGTH, code.code.length
    assert_match(/\A[A-Z0-9]+\z/, code.code)
  end

  test "generated code never contains the digit 7" do
    1000.times do
      code = InviteCode.new(user: users(:one))
      code.send(:generate_code)
      assert_no_match(/7/, code.code)
    end
  end

  test "code is unique" do
    code1 = invite_codes(:available)
    code2 = InviteCode.new(code: code1.code, user: users(:two))
    assert_not code2.valid?
    assert_includes code2.errors[:code], "has already been taken"
  end

  test "unused scope returns only unredeemed codes" do
    unused = InviteCode.unused
    assert_includes unused, invite_codes(:available)
    assert_not_includes unused, invite_codes(:used)
  end

  test "used scope returns only redeemed codes" do
    used = InviteCode.used
    assert_includes used, invite_codes(:used)
    assert_not_includes used, invite_codes(:available)
  end

  test "redeemed? returns correct status" do
    assert_not invite_codes(:available).redeemed?
    assert invite_codes(:used).redeemed?
  end

  test "redeem! marks code as used" do
    code = invite_codes(:available)
    new_user = users(:two)

    code.redeem!(new_user)
    code.reload

    assert_equal new_user, code.redeemed_by
    assert code.redeemed_at.present?
    assert code.redeemed?
  end

  test "belongs to user" do
    code = invite_codes(:available)
    assert_equal users(:one), code.user
  end

  test "does not overwrite manually set code" do
    code = InviteCode.new(code: "MANUAL99", user: users(:one))
    assert code.valid?
    assert_equal "MANUAL99", code.code
  end
end
