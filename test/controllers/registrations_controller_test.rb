require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "new renders sign up form" do
    get new_registration_path
    assert_response :success
  end

  test "create registers a new user with valid invite code" do
    invite = invite_codes(:available)

    assert_difference("User.count", 1) do
      post registration_path, params: {
        invite_code: invite.code,
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

    # Invite code should be marked as redeemed
    invite.reload
    assert invite.redeemed?
    assert_equal User.find_by(email_address: "newuser@example.com"), invite.redeemed_by
  end

  test "create rejects registration without invite code" do
    assert_no_difference("User.count") do
      post registration_path, params: {
        invite_code: "",
        user: {
          email_address: "newuser@example.com",
          password: "N3wUs3r!S1gnup#2026",
          password_confirmation: "N3wUs3r!S1gnup#2026"
        }
      }
    end
    assert_response :unprocessable_entity
    assert_match "Invalid or already used invite code", response.body
  end

  test "create rejects registration with already used invite code" do
    used_invite = invite_codes(:used)

    assert_no_difference("User.count") do
      post registration_path, params: {
        invite_code: used_invite.code,
        user: {
          email_address: "newuser@example.com",
          password: "N3wUs3r!S1gnup#2026",
          password_confirmation: "N3wUs3r!S1gnup#2026"
        }
      }
    end
    assert_response :unprocessable_entity
    assert_match "Invalid or already used invite code", response.body
  end

  test "create rejects registration with bogus invite code" do
    assert_no_difference("User.count") do
      post registration_path, params: {
        invite_code: "NOPE0000",
        user: {
          email_address: "newuser@example.com",
          password: "N3wUs3r!S1gnup#2026",
          password_confirmation: "N3wUs3r!S1gnup#2026"
        }
      }
    end
    assert_response :unprocessable_entity
  end

  test "invite code lookup is case-insensitive" do
    invite = invite_codes(:available)

    assert_difference("User.count", 1) do
      post registration_path, params: {
        invite_code: invite.code.downcase,
        user: {
          email_address: "casetest@example.com",
          password: "N3wUs3r!S1gnup#2026",
          password_confirmation: "N3wUs3r!S1gnup#2026"
        }
      }
    end
    assert_redirected_to new_session_path
  end

  test "create rejects invalid registration even with valid invite code" do
    invite = invite_codes(:available)

    assert_no_difference("User.count") do
      post registration_path, params: {
        invite_code: invite.code,
        user: {
          email_address: "",
          password: "short",
          password_confirmation: "short"
        }
      }
    end
    assert_response :unprocessable_entity

    # Invite code should not be consumed
    assert_not invite.reload.redeemed?
  end

  test "create rejects duplicate email" do
    invite = invite_codes(:available)

    assert_no_difference("User.count") do
      post registration_path, params: {
        invite_code: invite.code,
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
        invite_code: invite_codes(:available).code,
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
