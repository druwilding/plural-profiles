require "test_helper"

class Our::SearchControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  # The sidebar (rendered via OurSidebar on every "our" page) always lists ALL
  # of the user's groups and profiles for navigation, regardless of the search
  # query — and the search form echoes the query back into its input value —
  # so assertions must be scoped to just the results area to avoid false
  # positives/negatives from that noise.
  def main_content
    doc = Nokogiri::HTML5(response.body)
    doc.at_css(".main-content form")&.remove
    doc.at_css(".main-content").to_html
  end

  test "show redirects unauthenticated user" do
    get our_search_path
    assert_redirected_to new_session_path
  end

  test "show with no query renders empty state without results" do
    sign_in_as @user
    get our_search_path
    assert_response :success
    assert_no_match "Alice", main_content
    assert_no_match "Friends", main_content
  end

  test "show matches profile by name" do
    sign_in_as @user
    get our_search_path, params: { q: "Alice" }
    assert_response :success
    assert_match "Alice", main_content
    assert_no_match "Bob", main_content
  end

  test "show matches profile by pronouns" do
    sign_in_as @user
    get our_search_path, params: { q: "he/him" }
    assert_response :success
    assert_match "Bob", main_content
    assert_no_match "Alice", main_content
  end

  test "show matches profile by tag line" do
    sign_in_as @user
    get our_search_path, params: { q: "stargazing" }
    assert_response :success
    assert_match "Alice", main_content
    assert_no_match "Bob", main_content
  end

  test "show matches profile by description" do
    sign_in_as @user
    get our_search_path, params: { q: "painting" }
    assert_response :success
    assert_match "Alice", main_content
    assert_no_match "Bob", main_content
  end

  test "show matches a profile by its chat-only overridden name" do
    profiles(:alice).update!(mini_profile_name_inherited: false, mini_profile_name: "ChatAlice")
    sign_in_as @user
    get our_search_path, params: { q: "ChatAlice" }
    assert_response :success
    assert_match "Alice", main_content
  end

  test "show matches a profile by its chat-only overridden pronouns" do
    profiles(:alice).update!(mini_profile_pronouns_inherited: false, mini_profile_pronouns: "xe/xem")
    sign_in_as @user
    get our_search_path, params: { q: "xe/xem" }
    assert_response :success
    assert_match "Alice", main_content
  end

  test "show matches a profile by its chat-only overridden description, still finding it by the real name" do
    profiles(:bob).update!(mini_profile_description_inherited: false, mini_profile_description: "chat-only blurb about camping")
    sign_in_as @user
    get our_search_path, params: { q: "camping" }
    assert_response :success
    assert_match "Bob", main_content
    assert_no_match "Alice", main_content
  end

  test "show matches a group by its chat-only overridden tagline" do
    groups(:friends).update!(mini_profile_tag_line_inherited: false, mini_profile_tag_line: "chat-only rallying cry")
    sign_in_as @user
    get our_search_path, params: { q: "rallying cry" }
    assert_response :success
    assert_match "Friends", main_content
  end

  test "show still finds a profile by its real field even once a chat override exists on a different field" do
    profiles(:alice).update!(mini_profile_subtitle_inherited: false, mini_profile_subtitle: "unrelated chat subtitle")
    sign_in_as @user
    get our_search_path, params: { q: "stargazing" }
    assert_response :success
    assert_match "Alice", main_content
  end

  test "show matches group by name" do
    sign_in_as @user
    get our_search_path, params: { q: "Friends" }
    assert_response :success
    assert_match "Friends", main_content
    assert_no_match "Everyone Profile", main_content
  end

  test "show matches group by description" do
    sign_in_as @user
    get our_search_path, params: { q: "close friends" }
    assert_response :success
    assert_match "Friends", main_content
  end

  test "show matches group by pronouns" do
    groups(:friends).update!(pronouns: "they/them")
    sign_in_as @user
    get our_search_path, params: { q: "they/them" }
    assert_response :success
    assert_match "Friends", main_content
  end

  test "show matches by label" do
    sign_in_as @user
    profiles(:alice).update!(labels: [ "close-friends-only" ])
    get our_search_path, params: { q: "close-friends" }
    assert_response :success
    assert_match "Alice", main_content
    assert_no_match "Bob", main_content
  end

  test "show does not include other users' groups or profiles" do
    sign_in_as @user
    # "they/them" matches both the current user's own profile and Carol's
    # (owned by another user) — only the former should ever be returned.
    get our_search_path, params: { q: "they/them" }
    assert_response :success
    assert_match "Everyone Profile", main_content
    assert_no_match "Carol", main_content
  end

  test "show renders separate sections for groups and profiles" do
    sign_in_as @user
    get our_search_path, params: { q: "e" }
    assert_response :success
    assert_match "Groups", main_content
    assert_match "Profiles", main_content
  end
end
