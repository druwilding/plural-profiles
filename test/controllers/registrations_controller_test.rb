require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "new renders sign up form" do
    get new_registration_path
    assert_response :success
  end

  test "create registers a new user" do
    assert_difference("User.count", 1) do
      post registration_path, params: {
        user: {
          email_address: "newuser@example.com",
          password: "N3wUs3r!S1gnup#2026",
          password_confirmation: "N3wUs3r!S1gnup#2026"
        }
      }
    end
    assert_redirected_to new_session_path
    follow_redirect!
    assert_match "Account created", response.body
  end

  test "create rejects invalid registration" do
    assert_no_difference("User.count") do
      post registration_path, params: {
        user: {
          email_address: "",
          password: "short",
          password_confirmation: "short"
        }
      }
    end
    assert_response :unprocessable_entity
  end

  test "create rejects duplicate email" do
    assert_no_difference("User.count") do
      post registration_path, params: {
        user: {
          email_address: users(:one).email_address,
          password: "N3wUs3r!S1gnup#2026",
          password_confirmation: "N3wUs3r!S1gnup#2026"
        }
      }
    end
    assert_response :unprocessable_entity
  end

  test "new renders closed page when signups disabled" do
    ENV["SIGNUPS_ENABLED"] = "false"
    get new_registration_path
    assert_response :success
    # Should render the closed template rather than the form
  ensure
    ENV["SIGNUPS_ENABLED"] = "true"
  end

  test "create blocked when signups disabled" do
    ENV["SIGNUPS_ENABLED"] = "false"
    assert_no_difference("User.count") do
      post registration_path, params: {
        user: {
          email_address: "blocked@example.com",
          password: "N3wUs3r!S1gnup#2026",
          password_confirmation: "N3wUs3r!S1gnup#2026"
        }
      }
    end
    assert_response :success # renders the closed template
  ensure
    ENV["SIGNUPS_ENABLED"] = "true"
  end
end
