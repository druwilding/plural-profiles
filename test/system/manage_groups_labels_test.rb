require "application_system_test_case"

class ManageGroupsLabelsTest < ApplicationSystemTestCase
  setup do
    @user = users(:three)
    sign_in_via_browser
    @group = groups(:alpha_clan)
    @profile = profiles(:ember)
  end

  test "group labels appear in manage groups tree" do
    @group.update!(labels: %w[important testlabel])
    visit manage_groups_our_group_path(@group)
    # Find the first .tree-editor__folder--root (the root group node)
    within first(".tree-editor__folder--root .tree-editor__item-info") do
      assert_selector ".label-badges .label-badge", text: "important"
      assert_selector ".label-badges .label-badge", text: "testlabel"
    end
  end

  test "profile labels appear in manage groups tree" do
    @profile.update!(labels: %w[helper featured])
    visit manage_groups_our_group_path(@group)
    # Find the profile node by unique name and class
    within find(".tree-editor__leaf--profile", text: @profile.name, match: :first) do
      assert_selector ".label-badges .label-badge", text: "helper"
      assert_selector ".label-badges .label-badge", text: "featured"
    end
  end

  test "labels appear on a child group rendered as a leaf node" do
    # Create a leaf sub-group (no children, no profiles) with labels.
    # rogue_pack has a profile, so it renders as a folder - we need a true leaf.
    leaf = @user.groups.create!(name: "Leaf Group", labels: %w[nested leaf-label])
    @group.child_groups << leaf

    visit manage_groups_our_group_path(@group)

    within find(".tree-editor__leaf", text: "Leaf Group") do
      assert_selector ".label-badges .label-badge", text: "nested"
      assert_selector ".label-badges .label-badge", text: "leaf-label"
    end
  end
end
