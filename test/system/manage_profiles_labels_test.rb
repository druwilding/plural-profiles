require "application_system_test_case"

class ManageProfilesLabelsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in_via_browser
    @group = groups(:friends)
    @profile = profiles(:alice)
  end

  test "group labels appear in manage profiles title" do
    @group.update!(labels: %w[core trusted])
    visit manage_profiles_our_group_path(@group)
    within ".card .card__header" do
      assert_text "core"
      assert_text "trusted"
    end
  end

  test "profile labels appear on manage profiles cards" do
    @profile.update!(labels: %w[helper visible])
    @group.profiles << @profile unless @group.profiles.include?(@profile)
    visit manage_profiles_our_group_path(@group)
    within all(".profile-card").find { |card| card.has_text?(@profile.name) } do
      assert_selector ".label-badges .label-badge", text: "helper"
      assert_selector ".label-badges .label-badge", text: "visible"
    end
  end
end
