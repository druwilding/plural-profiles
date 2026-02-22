require "test_helper"

class Our::AccountControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @current_password = "Plur4l!Pr0files#2026"
  end

  # -- show --

  test "show renders account page" do
    sign_in_as @user
    get our_account_path
    assert_response :success
    assert_match "Account", response.body
    assert_match @user.email_address, response.body
  end

  test "show redirects unauthenticated user" do
    get our_account_path
    assert_redirected_to new_session_path
  end

  # -- update_password --

  test "update password with valid current and new password" do
    sign_in_as @user
    patch update_password_our_account_path, params: {
      current_password: @current_password,
      password: "NewSecure!Pass99",
      password_confirmation: "NewSecure!Pass99"
    }
    assert_redirected_to our_account_path
    follow_redirect!
    assert_match "Password updated.", response.body

    assert @user.reload.authenticate("NewSecure!Pass99")
  end

  test "update password rejects wrong current password" do
    sign_in_as @user
    patch update_password_our_account_path, params: {
      current_password: "wrong-password",
      password: "NewSecure!Pass99",
      password_confirmation: "NewSecure!Pass99"
    }
    assert_redirected_to our_account_path
    follow_redirect!
    assert_match "Current password is incorrect", response.body
  end

  test "update password rejects too-short new password" do
    sign_in_as @user
    patch update_password_our_account_path, params: {
      current_password: @current_password,
      password: "short",
      password_confirmation: "short"
    }
    assert_redirected_to our_account_path
    follow_redirect!
    assert_match "too short", response.body
  end

  test "update password rejects mismatched confirmation" do
    sign_in_as @user
    patch update_password_our_account_path, params: {
      current_password: @current_password,
      password: "NewSecure!Pass99",
      password_confirmation: "SomethingElse!99"
    }
    assert_redirected_to our_account_path
    follow_redirect!
    assert_match "doesn&#39;t match", response.body
  end

  test "update password redirects unauthenticated user" do
    patch update_password_our_account_path, params: {
      current_password: @current_password,
      password: "NewSecure!Pass99",
      password_confirmation: "NewSecure!Pass99"
    }
    assert_redirected_to new_session_path
  end
end
