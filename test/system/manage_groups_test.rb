require "application_system_test_case"

class ManageGroupsTest < ApplicationSystemTestCase
  setup do
    @user = users(:three)
    sign_in_via_browser
  end

  # -- Navigation & page rendering --

  test "navigate to manage groups from group show page" do
    visit our_group_path(groups(:alpha_clan))
    click_link "Manage groups"

    assert_current_path manage_groups_our_group_path(groups(:alpha_clan))
    assert_text "Manage groups in"
    assert_text "Alpha Clan"
  end

  test "manage groups shows full descendant tree regardless of inclusion modes" do
    visit manage_groups_our_group_path(groups(:alpha_clan))

    # Expand Spectrum to see its descendants
    expand_node("Spectrum")

    assert_text "Spectrum"
    assert_text "Prism Circle"

    # Rogue Pack is excluded from public view via override, but still visible in editor
    expand_node("Prism Circle")
    assert_text "Rogue Pack"
  end

  test "manage groups marks hidden nodes with tag" do
    visit manage_groups_our_group_path(groups(:alpha_clan))

    # Expand ancestors to reveal Rogue Pack (hidden via override)
    expand_node("Spectrum")
    expand_node("Prism Circle")

    rogue_summary = find("summary.tree-editor__summary", text: "Rogue Pack")
    within(rogue_summary) do
      assert_selector ".tree-editor__tag--hidden"
    end
  end

  test "manage groups shows override tag on nodes with overrides" do
    visit manage_groups_our_group_path(groups(:alpha_clan))

    # Prism Circle has an override — expand Spectrum to reveal it
    expand_node("Spectrum")

    prism_summary = find("summary.tree-editor__summary", text: "Prism Circle")
    within(prism_summary) do
      assert_selector ".tree-editor__tag--override"
    end
  end

  test "manage groups shows empty state when group has no sub-groups" do
    visit manage_groups_our_group_path(groups(:rogue_pack))

    assert_text "This group has no sub-groups yet. Add one below."
  end

  test "manage groups shows profiles hidden tag" do
    visit manage_groups_our_group_path(groups(:castle_clan))

    # Flux has include_direct_profiles: false — its summary should have the profiles-hidden tag
    flux_summary = find_node_summary_exact("Flux")
    within(flux_summary) do
      assert_selector ".tree-editor__tag--hidden"
    end
  end

  # -- Adding a sub-group --

  test "add a sub-group from manage groups" do
    alpha = groups(:alpha_clan)
    castle = groups(:castle_clan)

    visit manage_groups_our_group_path(alpha)

    assert_text "Add a group to"

    within(".card-list") do
      card = find(".card", text: castle.name)
      within(card) { click_link "Add" }
    end

    assert_current_path manage_groups_our_group_path(alpha)
    assert_text "Group added."

    within(".tree-editor__tree") do
      assert_text "Castle Clan"
    end
  end

  test "shows message when all groups are already in tree" do
    user = users(:one)
    sign_in_via_browser(user: user)

    visit manage_groups_our_group_path(groups(:everyone))

    assert_text "All your other groups are already in this tree."
  end

  # -- Removing a direct sub-group --

  test "remove a direct sub-group from manage groups" do
    alpha = groups(:alpha_clan)

    visit manage_groups_our_group_path(alpha)

    expand_node("Spectrum")

    accept_confirm do
      click_link "Remove from Alpha Clan"
    end

    assert_current_path manage_groups_our_group_path(alpha)
    assert_text "Group removed."

    # Spectrum was the only child — empty state should appear
    assert_text "This group has no sub-groups yet. Add one below."
  end

  # -- Configuring direct child (depth 1) --

  test "change direct child inclusion mode from all to none" do
    alpha = groups(:alpha_clan)

    visit manage_groups_our_group_path(alpha)

    expand_node("Spectrum")

    within(node_details("Spectrum")) do
      choose "None", match: :first
      click_button "Save"
    end

    assert_text "Relationship updated."

    link = group_groups(:spectrum_in_alpha)
    assert_equal "none", link.reload.inclusion_mode
  end

  test "change direct child inclusion mode to selected" do
    alpha = groups(:alpha_clan)

    visit manage_groups_our_group_path(alpha)

    expand_node("Spectrum")

    within(node_details("Spectrum")) do
      choose "Selected", match: :first
      uncheck "Prism Circle"
      click_button "Save"
    end

    assert_text "Relationship updated."

    link = group_groups(:spectrum_in_alpha)
    assert_equal "selected", link.reload.inclusion_mode
    assert_not_includes link.included_subgroup_ids, groups(:prism_circle).id
  end

  test "toggle include_direct_profiles on for direct child" do
    castle = groups(:castle_clan)

    visit manage_groups_our_group_path(castle)

    # Flux has include_direct_profiles: false — switch to All
    expand_node_exact("Flux")

    within(node_details_exact("Flux")) do
      within(find("fieldset", text: /Profiles/i)) do
        choose "All"
      end
      click_button "Save"
    end

    assert_text "Relationship updated."

    link = group_groups(:flux_in_castle)
    assert link.reload.include_direct_profiles
  end

  test "toggle include_direct_profiles off and on" do
    castle = groups(:castle_clan)

    visit manage_groups_our_group_path(castle)

    # First toggle Flux profiles to All (currently false)
    expand_node_exact("Flux")

    within(node_details_exact("Flux")) do
      within(find("fieldset", text: /Profiles/i)) do
        choose "All"
      end
      click_button "Save"
    end

    assert_text "Relationship updated."
    link = group_groups(:flux_in_castle)
    assert link.reload.include_direct_profiles

    # Now toggle back to None
    expand_node_exact("Flux")

    within(node_details_exact("Flux")) do
      within(find("fieldset", text: /Profiles/i)) do
        choose "None"
      end
      click_button "Save"
    end

    assert_text "Relationship updated."
    assert_not link.reload.include_direct_profiles
  end

  # -- Configuring deeper descendants (depth 2+) via overrides --

  test "deeper descendant with no sub-groups or profiles shows nothing to configure" do
    alpha = groups(:alpha_clan)
    castle = groups(:castle_clan)

    # Add Castle Clan to Alpha Clan so Castle Flux becomes a deeper descendant
    visit manage_groups_our_group_path(alpha)
    within(".card-list") do
      within(find(".card", text: castle.name)) { click_link "Add" }
    end
    assert_text "Group added."

    # Expand down to Castle Flux (no sub-groups, no profiles)
    expand_node_exact("Castle Clan")
    expand_node_exact("Castle Flux")

    within(node_details_exact("Castle Flux")) do
      assert_text "Nothing to configure"
      assert_no_button "Set override"
      assert_no_button "Save override"
    end
  end

  test "set an override on a deeper descendant" do
    castle = groups(:castle_clan)

    visit manage_groups_our_group_path(castle)

    expand_node_exact("Flux")
    expand_node("Echo Shard")

    within(node_details("Echo Shard")) do
      assert_text "No override set"
      click_button "Set override"
    end

    assert_current_path manage_groups_our_group_path(castle)
    assert_text "Override saved."

    edge = group_groups(:flux_in_castle)
    override = InclusionOverride.find_by(group_group: edge, target_group: groups(:echo_shard))
    assert override.present?, "Override should have been created for Echo Shard"
  end

  test "clear an existing override" do
    alpha = groups(:alpha_clan)

    visit manage_groups_our_group_path(alpha)

    expand_node("Spectrum")
    expand_node("Prism Circle")

    within(node_details("Prism Circle")) do
      assert_text "Override active"
      accept_confirm do
        click_link "Clear override"
      end
    end

    assert_current_path manage_groups_our_group_path(alpha)
    assert_text "Override cleared."

    edge = group_groups(:spectrum_in_alpha)
    assert_nil InclusionOverride.find_by(group_group: edge, target_group: groups(:prism_circle))
  end

  test "saving override changes mode on deeper descendant" do
    alpha = groups(:alpha_clan)

    visit manage_groups_our_group_path(alpha)

    expand_node("Spectrum")
    expand_node("Prism Circle")

    within(node_details("Prism Circle")) do
      assert_text "Override active"
      choose "All", match: :first
      click_button "Save override"
    end

    assert_text "Override saved."

    override = inclusion_overrides(:rogue_pack_excluded_from_alpha)
    assert_equal "all", override.reload.inclusion_mode
  end

  # -- Verifying public effects of manage groups changes --

  test "clearing override makes previously hidden group visible publicly" do
    alpha = groups(:alpha_clan)

    # Verify Rogue Pack is hidden publicly
    visit group_path(alpha.uuid)
    within(".explorer__sidebar") do
      assert_no_text "Rogue Pack"
    end

    # Change the override via manage groups
    sign_in_via_browser
    visit manage_groups_our_group_path(alpha)

    expand_node("Spectrum")
    expand_node("Prism Circle")

    within(node_details("Prism Circle")) do
      choose "All", match: :first
      click_button "Save override"
    end

    assert_text "Override saved."

    # Now Rogue Pack should appear publicly
    visit group_path(alpha.uuid)
    within(".explorer__sidebar") do
      assert_text "Rogue Pack"
    end
  end

  test "setting direct child to none hides its descendants publicly" do
    alpha = groups(:alpha_clan)

    visit manage_groups_our_group_path(alpha)

    expand_node("Spectrum")

    within(node_details("Spectrum")) do
      choose "None", match: :first
      click_button "Save"
    end

    assert_text "Relationship updated."

    visit group_path(alpha.uuid)
    within(".explorer__sidebar") do
      assert_text "Spectrum"
      assert_no_text "Prism Circle"
    end
  end

  test "removing sub-group via manage groups removes it from public view" do
    alpha = groups(:alpha_clan)

    # Verify visible publicly
    visit group_path(alpha.uuid)
    within(".explorer__sidebar") do
      assert_text "Spectrum"
    end

    sign_in_via_browser
    visit manage_groups_our_group_path(alpha)

    expand_node("Spectrum")

    accept_confirm do
      click_link "Remove from Alpha Clan"
    end

    assert_text "Group removed."

    # Verify gone from public view
    visit group_path(alpha.uuid)
    assert_no_text "Spectrum"
  end

  # -- Castle Clan fixture: selected mode --

  test "castle clan manage groups shows correct hidden state for flux children" do
    castle = groups(:castle_clan)

    visit manage_groups_our_group_path(castle)

    expand_node_exact("Flux")

    # Static Burst should have a hidden tag (not in selected list)
    static_summary = find("summary.tree-editor__summary", text: "Static Burst")
    within(static_summary) do
      assert_selector ".tree-editor__tag--hidden"
    end

    # Echo Shard should NOT have a hidden tag (it's in the selected list)
    echo_summary = find("summary.tree-editor__summary", text: "Echo Shard")
    within(echo_summary) do
      assert_no_selector ".tree-editor__tag--hidden"
    end
  end

  # -- Back link --

  test "back link returns to group show page" do
    alpha = groups(:alpha_clan)
    visit manage_groups_our_group_path(alpha)

    click_link "← Back to group"

    assert_current_path our_group_path(alpha)
  end

  private

  def sign_in_via_browser(user: nil)
    user ||= @user
    visit new_session_path
    fill_in "Email address", with: user.email_address
    fill_in "Password", with: "Plur4l!Pr0files#2026"
    click_button "Sign in"
    assert_current_path root_path
  end

  # Click a node's summary to expand it. Partial text match.
  def expand_node(name)
    find("summary.tree-editor__summary", text: name).click
  end

  # Click a node's summary using exact name match on the <strong> element.
  def expand_node_exact(name)
    target = all("summary.tree-editor__summary").find do |s|
      s.find("strong.tree-editor__name").text.strip == name
    end
    assert target, "Expected to find tree node named '#{name}'"
    target.click
  end

  # Find a node's summary by exact <strong> name match.
  def find_node_summary_exact(name)
    target = all("summary.tree-editor__summary").find do |s|
      s.find("strong.tree-editor__name").text.strip == name
    end
    assert target, "Expected to find tree node summary named '#{name}'"
    target
  end

  # Find the <details> element whose own summary <strong> matches the name.
  def node_details(name)
    target = all("details.tree-editor__details").find do |d|
      strong = d.first("summary.tree-editor__summary > .tree-editor__summary-row strong.tree-editor__name")
      strong&.text&.strip == name
    end
    assert target, "Expected to find tree node details for '#{name}'"
    target
  end

  alias_method :node_details_exact, :node_details
end
