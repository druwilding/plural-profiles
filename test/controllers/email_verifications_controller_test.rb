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

  # -- email change verification --

  test "email change token swaps to new email" do
    @user.update!(unverified_email_address: "new@example.com", email_verified_at: Time.current)

    token = @user.generate_token_for(:email_change)
    get email_verification_path(token: token)

    assert_redirected_to new_session_path
    follow_redirect!
    assert_match "Email address updated", response.body

    @user.reload
    assert_equal "new@example.com", @user.email_address
    assert_nil @user.unverified_email_address
    assert_not_nil @user.email_verified_at
    assert_equal 0, @user.sessions.count
  end

  test "expired email change token is rejected" do
    @user.update!(unverified_email_address: "new@example.com")

    token = @user.generate_token_for(:email_change)
    travel 25.hours do
      get email_verification_path(token: token)

      assert_redirected_to new_session_path
      follow_redirect!
      assert_match "Invalid or expired", response.body
    end

    assert_equal "one@example.com", @user.reload.email_address
  end

  test "email change token without pending email is harmless" do
    @user.update!(unverified_email_address: "old@example.com")
    token = @user.generate_token_for(:email_change)
    @user.update!(unverified_email_address: nil)

    get email_verification_path(token: token)

    assert_redirected_to new_session_path
    follow_redirect!
    assert_match "Invalid or expired", response.body

    assert_equal "one@example.com", @user.reload.email_address
  end

  test "email change token is invalidated when unverified email changes" do
    @user.update!(unverified_email_address: "first@example.com")
    token_for_first = @user.generate_token_for(:email_change)

    @user.update!(unverified_email_address: "second@example.com")

    get email_verification_path(token: token_for_first)

    assert_redirected_to new_session_path
    follow_redirect!
    assert_match "Invalid or expired", response.body

    @user.reload
    assert_equal "one@example.com", @user.email_address
    assert_equal "second@example.com", @user.unverified_email_address
  end
end
