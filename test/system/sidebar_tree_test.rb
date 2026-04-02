require "application_system_test_case"

class SidebarTreeTest < ApplicationSystemTestCase
  # ── Tree structure ────────────────────────────────────────────────────────

  test "top-level groups appear as expandable tree roots" do
    @user = users(:one)
    sign_in_via_browser

    # "Everyone" is the sole top-level group for user :one.
    # It has children so it renders as a <details> folder.
    within("nav.sidebar") do
      assert_selector ".sidebar-tree details", text: /Everyone/
    end
  end

  # ── Nested content ────────────────────────────────────────────────────────

  test "child groups and profiles appear nested under their parent group" do
    @user = users(:one)
    sign_in_via_browser

    # Scope to the sidebar nav — Friends and Alice both live in the groups tree
    within("nav.sidebar") do
      assert_text "Friends"
      assert_text "Alice"
    end
  end

  # ── Repeated items ────────────────────────────────────────────────────────

  test "second occurrence of a group carries the repeated style" do
    @user = users(:three)
    sign_in_via_browser

    # "Prism Circle" is reachable from alpha_clan via two paths:
    #   alpha_clan → Echo Shard → Prism Circle  (first, not repeated)
    #   alpha_clan → Spectrum   → Prism Circle  (second, repeated)
    # The second occurrence must have sidebar-tree__label--repeated applied.
    assert_selector ".sidebar-tree__label--repeated", text: "Prism Circle"
  end

  test "second occurrence of a profile carries the repeated style" do
    @user = users(:three)
    sign_in_via_browser

    # "Stray" is in prism_circle and rogue_pack (a child of prism_circle).
    # The profile is seen twice, so the second time it must be repeated.
    assert_selector ".sidebar-tree__label--repeated", text: "Stray"
  end

  # ── Profiles section ──────────────────────────────────────────────────────

  test "all profiles appear in the Profiles section" do
    @user = users(:one)
    sign_in_via_browser

    # The Profiles section is always visible and contains every profile.
    assert_text "Profiles"
    profiles_section = find("details[data-details-persist-key-value='sidebar-profiles']")
    within(profiles_section) do
      assert_text "Bob"
      assert_text "Alice"
      assert_text "Everyone Profile"
    end
  end

  test "profiles in a group also appear in the Profiles section" do
    @user = users(:one)
    sign_in_via_browser

    # Alice is in the Friends group AND still appears in the Profiles section.
    profiles_section = find("details[data-details-persist-key-value='sidebar-profiles']")
    within(profiles_section) { assert_text "Alice" }
  end

  # ── Active highlighting ───────────────────────────────────────────────────

  test "the current group page has its sidebar entry highlighted" do
    @user = users(:one)
    sign_in_via_browser

    visit our_group_path(groups(:friends))
    assert_current_path our_group_path(groups(:friends))

    # Friends has profiles so it renders as a folder; the summary row gets
    # the active class.
    assert_selector ".sidebar-tree__row--active .sidebar-tree__label", text: "Friends"
  end

  test "the current profile page has its sidebar entry highlighted" do
    @user = users(:one)
    sign_in_via_browser

    visit our_profile_path(profiles(:alice))
    assert_current_path our_profile_path(profiles(:alice))

    assert_selector ".sidebar-tree__leaf--active .sidebar-tree__label", text: "Alice"
  end

  # ── Expand all / Collapse all ────────────────────────────────────────────

  test "Collapse all closes every tree folder" do
    @user = users(:one)
    sign_in_via_browser

    # Both Everyone and its child Friends are open by default.
    assert_selector "details[data-details-persist-key-value^='sidebar-group-'][open]"

    click_button "Collapse all"

    # No tree-node folder should remain open.
    assert_no_selector "details[data-details-persist-key-value^='sidebar-group-'][open]"
  end

  test "Expand all re-opens all tree folders after they were collapsed" do
    @user = users(:one)
    sign_in_via_browser

    # Collapse everything first.
    click_button "Collapse all"
    assert_no_selector "details[data-details-persist-key-value^='sidebar-group-'][open]"

    click_button "Expand all"

    # Every tree-node folder should now be open.
    all_group_details = all("details[data-details-persist-key-value^='sidebar-group-']")
    assert all_group_details.any?, "Expected at least one group folder in the tree"
    all_group_details.each do |el|
      assert el["open"], "Expected details[data-details-persist-key-value='#{el['data-details-persist-key-value']}'] to be open"
    end
  end

  test "Collapse all persists closed state to localStorage" do
    @user = users(:one)
    sign_in_via_browser

    everyone_id = groups(:everyone).id
    storage_key = "details-persist:sidebar-group-#{everyone_id}"

    click_button "Collapse all"

    stored = page.evaluate_script("localStorage.getItem(#{storage_key.to_json})")
    assert_equal "closed", stored
  end

  # ── Expand / collapse persistence ─────────────────────────────────────────

  test "a collapsed Groups section remains collapsed after navigation" do
    @user = users(:one)
    sign_in_via_browser

    storage_key = "details-persist:sidebar-groups"

    # Persist "closed" for the top-level Groups section directly in localStorage.
    # Then navigate away and back so the Stimulus controller reconnects and reads it.
    page.execute_script("localStorage.setItem(#{storage_key.to_json}, 'closed')")

    visit our_profile_path(profiles(:alice))
    assert_current_path our_profile_path(profiles(:alice))

    visit our_groups_path
    assert_current_path our_groups_path

    # Stimulus connect() must have read 'closed' and removed [open].
    assert_no_selector "details[data-details-persist-key-value='sidebar-groups'][open]"
  end

  test "a collapsed group folder remains collapsed after navigation" do
    @user = users(:one)
    sign_in_via_browser

    everyone_id = groups(:everyone).id
    key         = "sidebar-group-#{everyone_id}"
    storage_key = "details-persist:#{key}"

    # Persist "closed" for the Everyone group folder directly in localStorage.
    # Then navigate away and back so the Stimulus controller reconnects and reads it.
    page.execute_script("localStorage.setItem(#{storage_key.to_json}, 'closed')")

    visit our_profile_path(profiles(:alice))
    assert_current_path our_profile_path(profiles(:alice))

    visit our_groups_path
    assert_current_path our_groups_path

    # Stimulus connect() must have read 'closed' and removed [open].
    assert_no_selector "details[data-details-persist-key-value='#{key}'][open]"
  end
end
