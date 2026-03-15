require "application_system_test_case"

class LabelsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @profile = profiles(:alice)
    @group = groups(:friends)
    sign_in_via_browser
  end

  # -- Profile labels display --

  test "labels appear on private profile show page" do
    @profile.update!(labels: %w[safe work])
    visit our_profile_path(@profile)

    assert_text "safe"
    assert_text "work"
  end

  test "labels appear on private profile index page" do
    @profile.update!(labels: %w[close-friends])
    visit our_profiles_path

    assert_text "close-friends"
  end

  test "labels do not appear on the public profile page" do
    @profile.update!(labels: %w[private-label])
    visit profile_path(@profile.uuid)

    assert_no_text "private-label"
  end

  # -- Group labels display --

  test "labels appear on private group show page" do
    @group.update!(labels: %w[safe work])
    visit our_group_path(@group)

    assert_text "safe"
    assert_text "work"
  end

  test "labels appear on private group index page" do
    @group.update!(labels: %w[close-friends])
    visit our_groups_path

    assert_text "close-friends"
  end

  test "labels do not appear on the public group page" do
    @group.update!(labels: %w[private-label])
    visit group_path(@group.uuid)

    assert_no_text "private-label"
  end

  # -- Label filtering on profile index --

  test "profile label filter narrows the list" do
    @profile.update!(labels: %w[public])
    profiles(:bob).update!(labels: %w[private])
    visit our_profiles_path

    within(".card-list") do
      assert_text "Alice"
      assert_text "Bob"
    end

    click_link "public"

    within(".card-list") do
      assert_text "Alice"
      assert_no_text "Bob"
    end
  end

  test "clear filter link restores full profile list" do
    @profile.update!(labels: %w[public])
    profiles(:bob).update!(labels: %w[private])
    visit our_profiles_path(label: "public")

    within(".card-list") { assert_no_text "Bob" }
    click_link "Clear filter"

    within(".card-list") do
      assert_text "Alice"
      assert_text "Bob"
    end
  end

  # -- Label filtering on group index --

  test "group label filter narrows the list" do
    @group.update!(labels: %w[public])
    groups(:everyone).update!(labels: %w[private])
    visit our_groups_path

    within(".card-list") do
      assert_text "Friends"
      assert_text "Everyone"
    end

    click_link "public"

    within(".card-list") do
      assert_text "Friends"
      assert_no_text "Everyone"
    end
  end

  test "clear filter link restores full group list" do
    @group.update!(labels: %w[public])
    groups(:everyone).update!(labels: %w[private])
    visit our_groups_path(label: "public")

    within(".card-list") { assert_no_text "Everyone" }
    click_link "Clear filter"

    within(".card-list") do
      assert_text "Friends"
      assert_text "Everyone"
    end
  end
end
