require "test_helper"

class EmailVerificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "valid token verifies email and redirects to sign in" do
    assert_nil @user.email_verified_at

    token = @user.signed_id(purpose: :email_verification)
    get email_verification_path(token: token)

    assert_redirected_to new_session_path
    follow_redirect!
    assert_match "Email verified", response.body

    @user.reload
    assert @user.email_verified?
    assert_not_nil @user.email_verified_at
  end

  test "invalid token redirects to sign in with error" do
    get email_verification_path(token: "bogus-token")

    assert_redirected_to new_session_path
    follow_redirect!
    assert_match "Invalid or expired", response.body
  end

  test "expired token redirects to sign in with error" do
    token = @user.signed_id(purpose: :email_verification, expires_in: 0.seconds)
    # Token is already expired
    travel 1.minute do
      get email_verification_path(token: token)

      assert_redirected_to new_session_path
      follow_redirect!
      assert_match "Invalid or expired", response.body
    end

    assert_nil @user.reload.email_verified_at
  end

  test "token with wrong purpose is rejected" do
    token = @user.signed_id(purpose: :password_reset)
    get email_verification_path(token: token)

    assert_redirected_to new_session_path
    follow_redirect!
    assert_match "Invalid or expired", response.body

    assert_nil @user.reload.email_verified_at
  end

  test "verifying twice is harmless" do
    token = @user.signed_id(purpose: :email_verification)

    get email_verification_path(token: token)
    assert_redirected_to new_session_path
    first_verified_at = @user.reload.email_verified_at

    travel 1.minute do
      get email_verification_path(token: token)
      assert_redirected_to new_session_path
      assert @user.reload.email_verified_at >= first_verified_at
    end
  end
end
