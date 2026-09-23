require "test_helper"

class Chat::MiniProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    host! "chat.example.com"
    @owner = users(:one)
    @other = users(:two)
    @profile = profiles(:alice)
    @group = groups(:friends)
  end

  test "show never renders an edit link, even for the owner" do
    sign_in_as @owner
    get chat_mini_profile_path("Profile", @profile.uuid)
    assert_response :success
    assert_no_match "Edit profile", response.body
  end

  test "show renders no link for anyone, owner included, when mini_profile_link_enabled is off" do
    assert_not @profile.mini_profile_link_enabled?
    [ @owner, @other ].each do |user|
      sign_in_as user
      get chat_mini_profile_path("Profile", @profile.uuid)
      assert_response :success
      assert_no_match "View full profile page", response.body
      sign_out
    end
  end

  test "show renders the view-full-page link for a non-owner when mini_profile_link_enabled is on" do
    @profile.update!(mini_profile_link_enabled: true)
    sign_in_as @other
    get chat_mini_profile_path("Profile", @profile.uuid)
    assert_response :success
    assert_match "View full profile page", response.body
    assert_match profile_path(@profile.uuid), response.body
  end

  test "the view-full-page link points at the main domain, not the chat subdomain the popover was fetched from" do
    # A bare profile_path/group_path is host-relative — it would resolve
    # against chat.example.com (wherever the popover itself was fetched
    # from) rather than the main site, since the full-page views aren't
    # chat-namespaced routes. A plain substring match on profile_path's
    # output wouldn't have caught that (a relative path is a substring of
    # the correct absolute one too) — this checks the actual href.
    @profile.update!(mini_profile_link_enabled: true)
    sign_in_as @other
    get chat_mini_profile_path("Profile", @profile.uuid)
    assert_response :success

    link = Nokogiri::HTML::DocumentFragment.parse(response.body).css("a").find { |a| a.text == "View full profile page" }
    assert link, "expected a <a>View full profile page</a> link in the response"
    assert_equal "http://example.com/profiles/#{@profile.uuid}", link["href"]
  end

  test "show renders the view-full-page link for the owner too, when mini_profile_link_enabled is on" do
    @profile.update!(mini_profile_link_enabled: true)
    sign_in_as @owner
    get chat_mini_profile_path("Profile", @profile.uuid)
    assert_response :success
    assert_match "View full profile page", response.body
  end

  test "show renders a group's view-full-page link when enabled" do
    @group.update!(mini_profile_link_enabled: true)
    sign_in_as @owner
    get chat_mini_profile_path("Group", @group.uuid)
    assert_response :success
    assert_match "View full group page", response.body
    assert_match group_path(@group.uuid), response.body
  end

  test "show renders a group's chat emotes, using the chat override" do
    @group.update!(emotes: ":red_heart:", mini_profile_emotes_inherited: false, mini_profile_emotes: ":aqua_heart: :aqua_heart:")
    sign_in_as @owner
    get chat_mini_profile_path("Group", @group.uuid)
    assert_response :success
    assert_equal [ "aqua heart", "aqua heart" ], css_select(".pronouns__emotes img").map { |img| img["alt"] }
  end

  test "show reflects an overridden chat identity, not the full profile" do
    @profile.update!(mini_profile_pronouns_inherited: false, mini_profile_pronouns: "it/its")
    sign_in_as @owner
    get chat_mini_profile_path("Profile", @profile.uuid)
    assert_response :success
    assert_match "it/its", response.body
    assert_no_match @profile.pronouns, response.body
  end

  test "show echoes a frame_id param back into the turbo-frame's id, for when the same postable posts more than once in a channel" do
    # mini_profile_frame_id(postable) alone is only unique per postable, not
    # per message — a caller (the message partial) that needs a page-unique
    # id passes it explicitly, and the response must echo the exact same id
    # back or Turbo can't match the fetched content to the requesting frame.
    sign_in_as @owner
    get chat_mini_profile_path("Profile", @profile.uuid, frame_id: "mini_profile_Profile_#{@profile.uuid}_12345")
    assert_response :success
    assert_match %r{<turbo-frame[^>]*id="mini_profile_Profile_#{@profile.uuid}_12345"}, response.body
  end

  test "show falls back to the plain postable-based frame id when no frame_id param is given" do
    sign_in_as @owner
    get chat_mini_profile_path("Profile", @profile.uuid)
    assert_response :success
    assert_match %r{<turbo-frame[^>]*id="mini_profile_Profile_#{@profile.uuid}"}, response.body
  end

  test "show 404s for an unknown uuid" do
    sign_in_as @owner
    get chat_mini_profile_path("Profile", "00000000-0000-0000-0000-000000000000")
    assert_response :not_found
  end

  test "show 404s for an invalid postable_type" do
    sign_in_as @owner
    # Built by hand: the route's own constraints: { postable_type: /Profile|Group/ }
    # means the path helper would raise UrlGenerationError before a request
    # is even made for anything else.
    get "/mini_profile/User/#{@profile.uuid}"
    assert_response :not_found
  end

  test "show redirects to sign-in when unauthenticated" do
    get chat_mini_profile_path("Profile", @profile.uuid)
    assert_redirected_to new_session_path
  end
end
