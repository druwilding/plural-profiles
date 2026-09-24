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

  test "update saves avatar_shape" do
    sign_in_as @user
    patch our_profile_path(@profile), params: {
      profile: { name: @profile.name, avatar_shape: "circle" }
    }
    assert_redirected_to our_profile_path(@profile)
    assert_equal "circle", @profile.reload.avatar_shape
  end

  test "update rejects invalid avatar_shape" do
    sign_in_as @user
    patch our_profile_path(@profile), params: {
      profile: { name: @profile.name, avatar_shape: "triangle" }
    }
    assert_response :unprocessable_entity
    assert_not_equal "triangle", @profile.reload.avatar_shape
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

  def created_at_parts_for(time)
    { month: time.strftime("%B"), day: time.day, year: time.year, hour: time.hour, minute: time.min }
  end

  test "update sets created_at to a past timestamp" do
    sign_in_as @user
    past = 1.year.ago.utc
    patch our_profile_path(@profile), params: {
      profile: { created_at_parts: created_at_parts_for(past) }
    }
    assert_redirected_to our_profile_path(@profile)
    assert_in_delta past.to_i, @profile.reload.created_at.to_i, 60
  end

  test "update accepts a created_at value in the future" do
    sign_in_as @user
    future = 1.day.from_now.utc
    patch our_profile_path(@profile), params: {
      profile: { created_at_parts: created_at_parts_for(future) }
    }
    assert_response :redirect
    assert_in_delta future.to_i, @profile.reload.created_at.to_i, 60
  end

  test "update accepts the month as a number as well as a name" do
    sign_in_as @user
    patch our_profile_path(@profile), params: {
      profile: { created_at_parts: { month: "3", day: "5", year: "2026", hour: "10", minute: "15" } }
    }
    assert_redirected_to our_profile_path(@profile)
    assert_equal Time.zone.local(2026, 3, 5, 10, 15), @profile.reload.created_at
  end

  test "update accepts zero-padded hour and minute values" do
    sign_in_as @user
    patch our_profile_path(@profile), params: {
      profile: { created_at_parts: { month: "3", day: "5", year: "2026", hour: "08", minute: "09" } }
    }
    assert_redirected_to our_profile_path(@profile)
    assert_equal Time.zone.local(2026, 3, 5, 8, 9), @profile.reload.created_at
  end

  test "update with malformed created_at does not raise" do
    sign_in_as @user
    original_created_at = @profile.created_at
    patch our_profile_path(@profile), params: {
      profile: { name: @profile.name, created_at_parts: { month: "not-a-month", day: "5", year: "2026", hour: "10", minute: "0" } }
    }
    # Malformed value is stripped in profile_params — update succeeds and
    # created_at is left unchanged.
    assert_redirected_to our_profile_path(@profile)
    assert_in_delta original_created_at.to_i, @profile.reload.created_at.to_i, 1
  end

  test "update with out-of-range created_at parts does not raise" do
    sign_in_as @user
    original_created_at = @profile.created_at
    patch our_profile_path(@profile), params: {
      profile: { name: @profile.name, created_at_parts: { month: "13", day: "40", year: "2026", hour: "25", minute: "99" } }
    }
    assert_redirected_to our_profile_path(@profile)
    assert_in_delta original_created_at.to_i, @profile.reload.created_at.to_i, 1
  end

  test "update rejects a day that doesn't exist in the given month" do
    sign_in_as @user
    original_created_at = @profile.created_at
    patch our_profile_path(@profile), params: {
      profile: { name: @profile.name, created_at_parts: { month: "February", day: "31", year: "2026", hour: "10", minute: "0" } }
    }
    assert_redirected_to our_profile_path(@profile)
    assert_in_delta original_created_at.to_i, @profile.reload.created_at.to_i, 1
  end

  test "edit renders created_at fields in the signed-in user's time zone" do
    @user.update!(time_zone: "Tokyo")
    @profile.update!(created_at: Time.utc(2026, 1, 15, 23, 30))
    sign_in_as @user
    get edit_our_profile_path(@profile)
    assert_response :success
    assert_match "Created at", response.body
    assert_no_match "Created at (UTC)", response.body
    assert_match %(<select id="created_at_month" name="profile[created_at_parts][month]">), response.body
    assert_match %(<option selected="selected" value="January">January</option>), response.body
    assert_match %(<select id="created_at_day" name="profile[created_at_parts][day]">), response.body
    assert_match %(<option selected="selected" value="16">16</option>), response.body
    assert_match %(id="created_at_year" name="profile[created_at_parts][year]" type="number" value="2026"), response.body
    assert_match %(<select id="created_at_hour" name="profile[created_at_parts][hour]">), response.body
    assert_match %(<option selected="selected" value="08">08</option>), response.body
    assert_match %(<select id="created_at_minute" name="profile[created_at_parts][minute]">), response.body
    assert_match %(<option selected="selected" value="30">30</option>), response.body
  end

  test "update interprets created_at in the signed-in user's time zone" do
    @user.update!(time_zone: "Tokyo")
    sign_in_as @user
    patch our_profile_path(@profile), params: {
      profile: { created_at_parts: { month: "January", day: "16", year: "2026", hour: "8", minute: "30" } }
    }
    assert_redirected_to our_profile_path(@profile)
    assert_equal Time.utc(2026, 1, 15, 23, 30), @profile.reload.created_at.utc
  end

  test "create saves subtitle and tag_line" do
    sign_in_as @user
    assert_difference("Profile.count", 1) do
      post our_profiles_path, params: {
        profile: { name: "New Alter", subtitle: "the quiet one", tag_line: "here to chill" }
      }
    end
    assert_redirected_to our_profile_path(Profile.last)
    assert_equal "the quiet one", Profile.last.subtitle
    assert_equal "here to chill", Profile.last.tag_line
  end

  test "update saves subtitle and tag_line" do
    sign_in_as @user
    patch our_profile_path(@profile), params: {
      profile: { name: @profile.name, subtitle: "updated subtitle", tag_line: "updated tagline" }
    }
    assert_redirected_to our_profile_path(@profile)
    assert_equal "updated subtitle", @profile.reload.subtitle
    assert_equal "updated tagline", @profile.reload.tag_line
  end

  test "show renders subtitle when present" do
    @profile.update!(subtitle: "the brave one")
    sign_in_as @user
    get our_profile_path(@profile)
    assert_response :success
    assert_match "the brave one", response.body
  end

  # -- Time zone rendering --

  test "show renders created_at in UTC when no preference or cookie is set" do
    @profile.update!(created_at: Time.utc(2026, 1, 15, 23, 30))
    sign_in_as @user
    get our_profile_path(@profile)
    assert_response :success
    assert_match "15 January 2026", response.body
  end

  test "show renders created_at in the signed-in user's time zone preference" do
    @user.update!(time_zone: "Tokyo")
    @profile.update!(created_at: Time.utc(2026, 1, 15, 23, 30))
    sign_in_as @user
    get our_profile_path(@profile)
    assert_response :success
    assert_match "16 January 2026", response.body
  end

  test "show renders created_at using the browser_time_zone cookie when no account preference is set" do
    @profile.update!(created_at: Time.utc(2026, 1, 15, 23, 30))
    sign_in_as @user
    cookies[:browser_time_zone] = "Asia/Tokyo"
    get our_profile_path(@profile)
    assert_response :success
    assert_match "16 January 2026", response.body
  end

  test "account time zone preference takes priority over the browser cookie" do
    @user.update!(time_zone: "UTC")
    @profile.update!(created_at: Time.utc(2026, 1, 15, 23, 30))
    sign_in_as @user
    cookies[:browser_time_zone] = "Asia/Tokyo"
    get our_profile_path(@profile)
    assert_response :success
    assert_match "15 January 2026", response.body
  end

  test "malformed browser_time_zone cookie falls back to UTC" do
    @profile.update!(created_at: Time.utc(2026, 1, 15, 23, 30))
    sign_in_as @user
    cookies[:browser_time_zone] = "Not/AZone"
    get our_profile_path(@profile)
    assert_response :success
    assert_match "15 January 2026", response.body
  end

  # -- Edge case: logged out user gets redirected to public --

  test "show redirects logged-out user to public profile" do
    get our_profile_path(@profile)
    assert_redirected_to profile_path(@profile.uuid)
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

  # -- Emotes --

  test "create saves emotes as typed" do
    sign_in_as @user
    post our_profiles_path, params: {
      profile: { name: "Hearty", emotes: ":red_heart: :dewdrop_heart: :red_heart:" }
    }
    assert_redirected_to our_profile_path(Profile.last)
    assert_equal ":red_heart: :dewdrop_heart: :red_heart:", Profile.last.emotes
  end

  test "update sets and clears emotes" do
    sign_in_as @user
    patch our_profile_path(@profile), params: { profile: { emotes: ":violet_heart:" } }
    assert_redirected_to our_profile_path(@profile)
    assert_equal ":violet_heart:", @profile.reload.emotes

    patch our_profile_path(@profile), params: { profile: { emotes: "" } }
    assert_equal "", @profile.reload.emotes
  end

  test "show displays emotes, including old codes" do
    sign_in_as @user
    @profile.update!(emotes: ":dewdrop_heart: :22_violet_heart:")
    get our_profile_path(@profile)
    assert_response :success
    assert_equal [ "dewdrop heart", "violet heart" ], css_select(".pronouns__emotes img").map { |img| img["alt"] }
  end

  test "the edit form has an emotes field with the emote picker" do
    sign_in_as @user
    get edit_our_profile_path(@profile)
    assert_select ".emote-input input[name='profile[emotes]']"
    assert_select "label[for=profile_emotes]", text: "Emotes"
  end

  # -- labels --

  test "create saves labels from comma-separated text" do
    sign_in_as @user
    post our_profiles_path, params: {
      profile: { name: "Labelled", labels_text: "safe, work" }
    }
    assert_redirected_to our_profile_path(Profile.last)
    assert_equal %w[safe work], Profile.last.labels
  end

  test "update saves labels" do
    sign_in_as @user
    patch our_profile_path(@profile), params: {
      profile: { labels_text: "close friends, family" }
    }
    assert_redirected_to our_profile_path(@profile)
    assert_equal [ "close friends", "family" ], @profile.reload.labels
  end

  test "update clears labels with blank text" do
    sign_in_as @user
    @profile.update!(labels: %w[safe work])
    patch our_profile_path(@profile), params: {
      profile: { labels_text: "" }
    }
    assert_redirected_to our_profile_path(@profile)
    assert_equal [], @profile.reload.labels
  end

  test "show displays labels on private page" do
    sign_in_as @user
    @profile.update!(labels: %w[safe work])
    get our_profile_path(@profile)
    assert_response :success
    assert_match "safe", response.body
    assert_match "work", response.body
  end

  test "index displays labels on profile cards" do
    sign_in_as @user
    @profile.update!(labels: %w[safe])
    get our_profiles_path
    assert_response :success
    assert_match "safe", response.body
  end

  test "labels do not appear on public profile page" do
    sign_in_as @user
    @profile.update!(labels: %w[safe work])
    get profile_path(@profile.uuid)
    assert_response :success
    assert_no_match "label-badge", response.body
  end

  # -- Label filtering --

  test "index shows all profiles when no label filter applied" do
    sign_in_as @user
    @profile.update!(labels: %w[public])
    get our_profiles_path
    assert_response :success
    assert_match "Alice", response.body
    assert_match "Bob", response.body
  end

  test "index filters profiles by label" do
    sign_in_as @user
    @profile.update!(labels: %w[public safe])
    bob = profiles(:bob)
    bob.update!(labels: %w[private])
    get our_profiles_path(label: "public")
    assert_response :success
    assert_select ".main-content h3 a", text: "Alice"
    assert_select ".main-content h3 a", text: "Bob", count: 0
  end

  test "index filter returns no profiles when no match" do
    sign_in_as @user
    @profile.update!(labels: %w[public])
    get our_profiles_path(label: "nonexistent")
    assert_response :success
    assert_select ".main-content .profile-grid", count: 0
  end

  test "index shows filter bar when labels exist" do
    sign_in_as @user
    @profile.update!(labels: %w[safe])
    get our_profiles_path
    assert_response :success
    assert_match "filter-bar", response.body
    assert_match "safe", response.body
  end

  test "index hides filter bar when no labels exist" do
    sign_in_as @user
    get our_profiles_path
    assert_response :success
    assert_no_match "filter-bar", response.body
  end

  test "index shows clear filter link when label filter is active" do
    sign_in_as @user
    @profile.update!(labels: %w[safe])
    get our_profiles_path(label: "safe")
    assert_response :success
    assert_match "Clear filter", response.body
  end

  test "index does not show clear filter link without active filter" do
    sign_in_as @user
    @profile.update!(labels: %w[safe])
    get our_profiles_path
    assert_response :success
    assert_no_match "Clear filter", response.body
  end

  # -- Theme dropdown --

  test "new form includes Our themes optgroup when user has personal themes" do
    sign_in_as @user
    get new_our_profile_path
    assert_response :success
    assert_select "select[name='profile[theme_id]'] optgroup[label='Our themes']"
    doc = Nokogiri::HTML(response.body)
    our_themes_optgroup = doc.at_css("select[name='profile[theme_id]'] optgroup[label='Our themes']")
    option_values = our_themes_optgroup.css("option").map { |opt| opt["value"].to_i }
    all_theme_ids = Theme.where(user: @user).pluck(:id)
    assert_equal all_theme_ids.sort, option_values.sort, "'Our themes' optgroup should include all user themes (personal and shared)"
  end

  test "new form includes Shared themes optgroup when shared themes exist" do
    sign_in_as @user
    get new_our_profile_path
    assert_response :success
    assert_select "select[name='profile[theme_id]'] optgroup[label='Shared themes']"
  end

  test "edit form preserves selected theme" do
    sign_in_as @user
    @profile.update!(theme: themes(:dark_forest))
    get edit_our_profile_path(@profile)
    assert_select "select[name='profile[theme_id]'] option[selected][value='#{themes(:dark_forest).id}']"
  end

  test "create with a personal theme_id saves the theme" do
    sign_in_as @user
    post our_profiles_path, params: {
      profile: { name: "Themed Profile", theme_id: themes(:dark_forest).id }
    }
    assert_redirected_to our_profile_path(Profile.last)
    assert_equal themes(:dark_forest), Profile.last.theme
  end

  test "create with a shared theme_id saves the theme" do
    sign_in_as @user
    post our_profiles_path, params: {
      profile: { name: "Themed Profile", theme_id: themes(:ocean_shared).id }
    }
    assert_redirected_to our_profile_path(Profile.last)
    assert_equal themes(:ocean_shared), Profile.last.theme
  end

  test "create with another user's non-shared theme_id is rejected" do
    sign_in_as @user
    assert_no_difference("Profile.count") do
      post our_profiles_path, params: {
        profile: { name: "Themed Profile", theme_id: themes(:other_user_theme).id }
      }
    end
    assert_response :unprocessable_entity
  end

  test "update changes a profile's theme" do
    sign_in_as @user
    patch our_profile_path(@profile), params: {
      profile: { theme_id: themes(:ocean_shared).id }
    }
    assert_redirected_to our_profile_path(@profile)
    assert_equal themes(:ocean_shared), @profile.reload.theme
  end

  test "update clears a profile's theme when blank is submitted" do
    sign_in_as @user
    @profile.update!(theme: themes(:dark_forest))
    patch our_profile_path(@profile), params: {
      profile: { theme_id: "" }
    }
    assert_redirected_to our_profile_path(@profile)
    assert_nil @profile.reload.theme
  end
end
