require "test_helper"

class Our::ChatIdentitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @profile = profiles(:alice)
    @group = groups(:friends)
    @other_user = users(:two)
    @other_profile = profiles(:carol)
  end

  # -- edit --

  test "edit renders for your own profile" do
    sign_in_as @user
    get edit_our_chat_identity_path("Profile", @profile.uuid)
    assert_response :success
    assert_match "Edit chat settings", response.body
  end

  test "edit renders for your own group" do
    sign_in_as @user
    get edit_our_chat_identity_path("Group", @group.uuid)
    assert_response :success
    assert_match "Edit chat settings", response.body
  end

  test "edit 404s for another user's profile" do
    sign_in_as @user
    get edit_our_chat_identity_path("Profile", @other_profile.uuid)
    assert_response :not_found
  end

  test "edit 404s for an invalid postable_type" do
    sign_in_as @user
    # Built by hand rather than the path helper: the route's own
    # `constraints: { postable_type: /Profile|Group/ }` means the helper
    # would raise ActionController::UrlGenerationError before a request is
    # even made — the case worth covering is an unmatched route, not that.
    get "/our/chat_identity/User/#{@profile.uuid}/edit"
    assert_response :not_found
  end

  test "edit redirects to sign-in when unauthenticated" do
    get edit_our_chat_identity_path("Profile", @profile.uuid)
    assert_redirected_to new_session_path
  end

  # -- update: persistence, independent of the full-profile fields --

  test "update persists mini-profile fields independently of the full-profile fields" do
    sign_in_as @user
    original_subtitle = @profile.subtitle

    patch our_chat_identity_path("Profile", @profile.uuid), params: {
      chat_identity: {
        mini_profile_subtitle_inherited: "false",
        mini_profile_subtitle: "Chat-only subtitle"
      }
    }

    assert_redirected_to edit_our_chat_identity_path("Profile", @profile.uuid)
    @profile.reload
    assert_equal "Chat-only subtitle", @profile.mini_profile_subtitle
    assert_not @profile.mini_profile_subtitle_inherited?
    assert_nil original_subtitle
    assert_nil @profile.subtitle
  end

  test "update persists chat_bracket fields" do
    sign_in_as @user
    patch our_chat_identity_path("Profile", @profile.uuid), params: {
      chat_identity: { chat_bracket_before: "al:" }
    }
    assert_redirected_to edit_our_chat_identity_path("Profile", @profile.uuid)
    assert_equal "al:", @profile.reload.chat_bracket_before
  end

  test "update persists pronouns and emotes overrides for a profile" do
    sign_in_as @user
    patch our_chat_identity_path("Profile", @profile.uuid), params: {
      chat_identity: {
        mini_profile_pronouns_inherited: "false",
        mini_profile_pronouns: "it/its",
        mini_profile_emotes_inherited: "false",
        mini_profile_emotes: ":aqua_heart: :moss_heart: :aqua_heart:"
      }
    }
    @profile.reload
    assert_equal "it/its", @profile.mini_profile_pronouns
    assert_equal ":aqua_heart: :moss_heart: :aqua_heart:", @profile.mini_profile_emotes
    assert_equal ":aqua_heart: :moss_heart: :aqua_heart:", @profile.chat_emotes
  end

  test "update persists pronouns override for a group" do
    sign_in_as @user
    patch our_chat_identity_path("Group", @group.uuid), params: {
      chat_identity: {
        mini_profile_pronouns_inherited: "false",
        mini_profile_pronouns: "they/them"
      }
    }
    @group.reload
    assert_equal "they/them", @group.mini_profile_pronouns
  end

  test "update persists an emotes override for a group" do
    sign_in_as @user
    patch our_chat_identity_path("Group", @group.uuid), params: {
      chat_identity: {
        mini_profile_emotes_inherited: "false",
        mini_profile_emotes: ":aqua_heart: :aqua_heart:"
      }
    }
    assert_response :redirect
    @group.reload
    assert_not @group.mini_profile_emotes_inherited?
    assert_equal ":aqua_heart: :aqua_heart:", @group.chat_emotes
  end

  test "edit shows an Emotes card for a group" do
    sign_in_as @user
    get edit_our_chat_identity_path("Group", @group.uuid)
    assert_select "h3", text: "Emotes"
    assert_select "input[name='chat_identity[mini_profile_emotes]']"
  end

  test "update rejects a blank name once set to not inherited" do
    sign_in_as @user
    patch our_chat_identity_path("Profile", @profile.uuid), params: {
      chat_identity: { mini_profile_name_inherited: "false", mini_profile_name: "" }
    }
    assert_response :unprocessable_entity
    assert_match "can&#39;t be blank when not inheriting the main name", response.body
  end

  test "update cannot touch another user's profile" do
    sign_in_as @user
    patch our_chat_identity_path("Profile", @other_profile.uuid), params: {
      chat_identity: { mini_profile_subtitle: "Hijacked" }
    }
    assert_response :not_found
  end

  test "update cannot touch another user's group" do
    other_group = groups(:family)
    sign_in_as @user
    patch our_chat_identity_path("Group", other_group.uuid), params: {
      chat_identity: { mini_profile_subtitle: "Hijacked" }
    }
    assert_response :not_found
    assert_nil other_group.reload.mini_profile_subtitle
  end

  test "update rejects a blank name once set to not inherited, for a group too" do
    sign_in_as @user
    patch our_chat_identity_path("Group", @group.uuid), params: {
      chat_identity: { mini_profile_name_inherited: "false", mini_profile_name: "" }
    }
    assert_response :unprocessable_entity
    assert_match "can&#39;t be blank when not inheriting the main name", response.body
  end

  test "update persists mini_profile_avatar_alt_text" do
    sign_in_as @user
    patch our_chat_identity_path("Profile", @profile.uuid), params: {
      chat_identity: { mini_profile_avatar_inherited: "false", mini_profile_avatar_alt_text: "A chat-only alt text" }
    }
    assert_equal "A chat-only alt text", @profile.reload.mini_profile_avatar_alt_text
  end

  # -- update: mini_profile_avatar upload/remove, independent of the main avatar --

  test "update attaches a mini_profile_avatar without touching the main avatar" do
    sign_in_as @user
    assert_not @profile.avatar.attached?

    patch our_chat_identity_path("Profile", @profile.uuid), params: {
      chat_identity: {
        mini_profile_avatar: fixture_file_upload("avatar.png", "image/png")
      }
    }

    @profile.reload
    assert @profile.mini_profile_avatar.attached?
    assert_not @profile.avatar.attached?
  end

  test "update with remove_mini_profile_avatar purges it without touching the main avatar" do
    sign_in_as @user
    @profile.mini_profile_avatar.attach(
      io: File.open(file_fixture("avatar.png")), filename: "avatar.png", content_type: "image/png"
    )
    @profile.avatar.attach(
      io: File.open(file_fixture("avatar.png")), filename: "avatar.png", content_type: "image/png"
    )

    patch our_chat_identity_path("Profile", @profile.uuid), params: {
      chat_identity: { remove_mini_profile_avatar: "1" }
    }

    @profile.reload
    assert_not @profile.mini_profile_avatar.attached?
    assert @profile.avatar.attached?
  end

  test "update with mini_profile_avatar_inherited true (Use main) purges an existing mini_profile_avatar" do
    sign_in_as @user
    @profile.mini_profile_avatar.attach(
      io: File.open(file_fixture("avatar.png")), filename: "avatar.png", content_type: "image/png"
    )
    @profile.avatar.attach(
      io: File.open(file_fixture("avatar.png")), filename: "avatar.png", content_type: "image/png"
    )

    patch our_chat_identity_path("Profile", @profile.uuid), params: {
      chat_identity: { mini_profile_avatar_inherited: "true" }
    }

    @profile.reload
    assert_not @profile.mini_profile_avatar.attached?
    assert @profile.avatar.attached?
  end

  test "update with mini_profile_avatar_inherited false saves an overridden shape without uploading a new image" do
    sign_in_as @user
    assert_not @profile.mini_profile_avatar.attached?

    patch our_chat_identity_path("Profile", @profile.uuid), params: {
      chat_identity: { mini_profile_avatar_inherited: "false", mini_profile_avatar_shape: "square" }
    }

    @profile.reload
    assert_not @profile.mini_profile_avatar_inherited?
    assert_equal "square", @profile.mini_profile_avatar_shape
    assert_not @profile.mini_profile_avatar.attached?
  end

  # -- preview --

  test "preview renders the mini-profile partial reflecting unsaved form values" do
    sign_in_as @user
    post preview_our_chat_identity_path("Profile", @profile.uuid), params: {
      chat_identity: {
        mini_profile_subtitle_inherited: "false",
        mini_profile_subtitle: "Preview-only subtitle"
      }
    }
    assert_response :success
    assert_match "Preview-only subtitle", response.body
    assert_nil @profile.reload.mini_profile_subtitle
  end

  test "preview shows nothing about the full-page link when mini_profile_link_enabled is off" do
    sign_in_as @user
    assert_not @profile.mini_profile_link_enabled?
    post preview_our_chat_identity_path("Profile", @profile.uuid), params: {
      chat_identity: { mini_profile_subtitle: "" }
    }
    assert_response :success
    assert_no_match "Edit profile", response.body
    assert_no_match "View full profile page", response.body
  end

  test "preview cannot be pointed at another user's profile" do
    sign_in_as @user
    post preview_our_chat_identity_path("Profile", @other_profile.uuid), params: {
      chat_identity: { mini_profile_subtitle_inherited: "false", mini_profile_subtitle: "Snooped" }
    }
    assert_response :not_found
    assert_nil @other_profile.reload.mini_profile_subtitle
  end

  test "preview redirects to sign-in when unauthenticated" do
    post preview_our_chat_identity_path("Profile", @profile.uuid), params: {
      chat_identity: { mini_profile_subtitle: "Anonymous" }
    }
    assert_redirected_to new_session_path
  end

  test "preview shows the full-page link pointing at # instead of the real destination, when enabled" do
    sign_in_as @user
    post preview_our_chat_identity_path("Profile", @profile.uuid), params: {
      chat_identity: { mini_profile_link_enabled: "1" }
    }
    assert_response :success
    assert_match %r{<a [^>]*href="#"[^>]*>View full profile page</a>}, response.body
    assert_match "chat-identity-form#preventDefault", response.body
    assert_no_match "rel=\"noopener\"", response.body
  end
end
