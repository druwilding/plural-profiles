require "test_helper"

class Our::ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @profile = profiles(:alice)
    @other_user = users(:two)
    @other_profile = profiles(:carol)
  end

  # -- Authenticated happy paths --

  test "index lists current user profiles" do
    sign_in_as @user
    get our_profiles_path
    assert_response :success
    assert_match "Alice", response.body
    assert_match "Bob", response.body
    assert_no_match "Carol", response.body
  end

  test "show displays own profile" do
    sign_in_as @user
    get our_profile_path(@profile)
    assert_response :success
    assert_match "Alice", response.body
  end

  test "new renders form" do
    sign_in_as @user
    get new_our_profile_path
    assert_response :success
  end

  test "create saves a valid profile" do
    sign_in_as @user
    assert_difference("Profile.count", 1) do
      post our_profiles_path, params: {
        profile: { name: "New Alter", pronouns: "xe/xem", description: "Hello!" }
      }
    end
    assert_redirected_to our_profile_path(Profile.last)
    follow_redirect!
    assert_match "Profile created.", response.body
  end

  test "create rejects blank name" do
    sign_in_as @user
    assert_no_difference("Profile.count") do
      post our_profiles_path, params: {
        profile: { name: "", pronouns: "", description: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "edit renders form for own profile" do
    sign_in_as @user
    get edit_our_profile_path(@profile)
    assert_response :success
  end

  test "update changes profile attributes" do
    sign_in_as @user
    patch our_profile_path(@profile), params: {
      profile: { name: "Alice Updated" }
    }
    assert_redirected_to our_profile_path(@profile)
    follow_redirect!
    assert_match "Profile updated.", response.body
    assert_equal "Alice Updated", @profile.reload.name
  end

  test "update with avatar upload" do
    sign_in_as @user
    patch our_profile_path(@profile), params: {
      profile: {
        avatar: fixture_file_upload("avatar.png", "image/png"),
        avatar_alt_text: "A photo of Alice"
      }
    }
    assert_redirected_to our_profile_path(@profile)
    assert @profile.reload.avatar.attached?
    assert_equal "A photo of Alice", @profile.avatar_alt_text
  end

  test "update with remove_avatar purges avatar" do
    sign_in_as @user
    @profile.avatar.attach(
      io: File.open(file_fixture("avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    assert @profile.avatar.attached?

    patch our_profile_path(@profile), params: {
      profile: { name: @profile.name, remove_avatar: "1" }
    }
    assert_redirected_to our_profile_path(@profile)
    assert_not @profile.reload.avatar.attached?
  end

  test "update rejects non-image avatar" do
    sign_in_as @user
    patch our_profile_path(@profile), params: {
      profile: {
        name: @profile.name,
        avatar: Rack::Test::UploadedFile.new(StringIO.new("<script>alert('xss')</script>"), "text/html", false, original_filename: "evil.html")
      }
    }
    assert_response :unprocessable_entity
    assert_not @profile.reload.avatar.attached?
  end

  test "destroy deletes profile" do
    sign_in_as @user
    assert_difference("Profile.count", -1) do
      delete our_profile_path(@profile)
    end
    assert_redirected_to our_profiles_path
  end

  test "update sets created_at to a past timestamp" do
    sign_in_as @user
    past = 1.year.ago.utc
    patch our_profile_path(@profile), params: {
      profile: { created_at: past.strftime("%Y-%m-%dT%H:%M") }
    }
    assert_redirected_to our_profile_path(@profile)
    assert_in_delta past.to_i, @profile.reload.created_at.to_i, 60
  end

  test "update rejects a created_at value in the future" do
    sign_in_as @user
    future = 1.day.from_now.utc
    patch our_profile_path(@profile), params: {
      profile: { created_at: future.strftime("%Y-%m-%dT%H:%M") }
    }
    assert_response :unprocessable_entity
    assert_match "can&#39;t be in the future", response.body
  end

  test "update with malformed created_at does not raise" do
    sign_in_as @user
    original_created_at = @profile.created_at
    patch our_profile_path(@profile), params: {
      profile: { name: @profile.name, created_at: "not-a-date" }
    }
    # Malformed value is stripped in profile_params — update succeeds and
    # created_at is left unchanged.
    assert_redirected_to our_profile_path(@profile)
    assert_in_delta original_created_at.to_i, @profile.reload.created_at.to_i, 1
  end

  # -- Edge case: logged out user gets redirected to public --

  test "show redirects logged-out user to public profile" do
    get our_profile_path(@profile)
    assert_redirected_to profile_path(@profile.uuid)
    follow_redirect!
    assert_response :success
    assert_match "Alice", response.body
    assert_no_match "Edit", response.body
    assert_no_match "Delete", response.body
    assert_no_match "Share this profile", response.body
  end

  test "index redirects logged-out user to sign in" do
    get our_profiles_path
    assert_redirected_to new_session_path
  end

  test "new redirects logged-out user to sign in" do
    get new_our_profile_path
    assert_redirected_to new_session_path
  end

  test "create redirects logged-out user to sign in" do
    post our_profiles_path, params: { profile: { name: "Nope" } }
    assert_redirected_to new_session_path
  end

  test "edit redirects logged-out user to sign in" do
    get edit_our_profile_path(@profile)
    assert_redirected_to new_session_path
  end

  test "update redirects logged-out user to sign in" do
    patch our_profile_path(@profile), params: { profile: { name: "Nope" } }
    assert_redirected_to new_session_path
  end

  test "destroy redirects logged-out user to sign in" do
    delete our_profile_path(@profile)
    assert_redirected_to new_session_path
  end

  # -- Edge case: wrong user gets redirected to public --

  test "show redirects wrong user to public profile" do
    sign_in_as @other_user
    get our_profile_path(@profile)
    assert_redirected_to profile_path(@profile.uuid)
    follow_redirect!
    assert_response :success
    assert_match "Alice", response.body
    assert_no_match "Edit", response.body
    assert_no_match "Delete", response.body
    assert_no_match "Share this profile", response.body
  end

  test "edit redirects wrong user to public profile" do
    sign_in_as @other_user
    get edit_our_profile_path(@profile)
    assert_redirected_to profile_path(@profile.uuid)
  end

  test "update redirects wrong user to public profile" do
    sign_in_as @other_user
    patch our_profile_path(@profile), params: { profile: { name: "Hacked" } }
    assert_redirected_to profile_path(@profile.uuid)
    assert_equal "Alice", @profile.reload.name
  end

  test "destroy redirects wrong user to public profile" do
    sign_in_as @other_user
    assert_no_difference("Profile.count") do
      delete our_profile_path(@profile)
    end
    assert_redirected_to profile_path(@profile.uuid)
  end

  # -- regenerate_uuid --

  test "regenerate_uuid changes the uuid and redirects with notice" do
    sign_in_as @user
    old_uuid = @profile.uuid
    patch regenerate_uuid_our_profile_path(@profile)
    assert_redirected_to our_profile_path(@profile.reload)
    assert_not_equal old_uuid, @profile.uuid
    follow_redirect!
    assert_match "Share URL regenerated.", response.body
  end

  test "regenerate_uuid does not contain the digit 7" do
    sign_in_as @user
    patch regenerate_uuid_our_profile_path(@profile)
    assert_no_match(/7/, @profile.reload.uuid)
  end

  test "regenerate_uuid redirects logged-out user to sign in" do
    patch regenerate_uuid_our_profile_path(@profile)
    assert_redirected_to new_session_path
    assert_equal profiles(:alice).uuid, @profile.reload.uuid
  end

  test "regenerate_uuid redirects wrong user to public profile" do
    sign_in_as @other_user
    old_uuid = @profile.uuid
    patch regenerate_uuid_our_profile_path(@profile)
    assert_redirected_to profile_path(@profile.uuid)
    assert_equal old_uuid, @profile.reload.uuid
  end

  # -- Heart emojis --

  test "create with heart emojis saves them" do
    sign_in_as @user
    post our_profiles_path, params: {
      profile: { name: "Hearty", heart_emojis: %w[01_dewdrop_heart 36_red_heart] }
    }
    assert_redirected_to our_profile_path(Profile.last)
    assert_equal %w[01_dewdrop_heart 36_red_heart], Profile.last.heart_emojis
  end

  test "update sets heart emojis" do
    sign_in_as @user
    patch our_profile_path(@profile), params: {
      profile: { heart_emojis: %w[22_violet_heart] }
    }
    assert_redirected_to our_profile_path(@profile)
    assert_equal %w[22_violet_heart], @profile.reload.heart_emojis
  end

  test "update clears heart emojis with empty array" do
    sign_in_as @user
    @profile.update!(heart_emojis: %w[01_dewdrop_heart])
    patch our_profile_path(@profile), params: {
      profile: { heart_emojis: [ "" ] }
    }
    assert_redirected_to our_profile_path(@profile)
    assert_equal [], @profile.reload.heart_emojis
  end

  test "update rejects invalid heart emojis" do
    sign_in_as @user
    patch our_profile_path(@profile), params: {
      profile: { heart_emojis: %w[totally_fake_heart] }
    }
    assert_response :unprocessable_entity
  end

  test "show displays heart emojis" do
    sign_in_as @user
    @profile.update!(heart_emojis: %w[01_dewdrop_heart 22_violet_heart])
    get our_profile_path(@profile)
    assert_response :success
    assert_match "Heart emojis", response.body
    assert_match "01_dewdrop_heart.webp", response.body
    assert_match "22_violet_heart.webp", response.body
  end

  test "show does not display heart section when none selected" do
    sign_in_as @user
    @profile.update!(heart_emojis: [])
    get our_profile_path(@profile)
    assert_response :success
    assert_no_match "Heart emojis", response.body
  end
end
