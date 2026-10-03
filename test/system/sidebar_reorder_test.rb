require "application_system_test_case"

class SidebarReorderTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @everyone = groups(:everyone)
    @friends = groups(:friends)
    @bob = profiles(:bob)
    @everyone_profile = profiles(:everyone_profile)
    @alice = profiles(:alice)
    @everyone.group_profiles.create!(profile: @bob)

    sign_in_via_browser(@user)
    visit our_profiles_path
  end

  test "reorder mode adds handles and move buttons, and Done takes them away" do
    assert_no_selector ".reorder-handle"
    click_button "Reorder"

    assert_selector ".sidebar--reordering"
    assert_selector "[data-sidebar-reorder-target='status']", text: "Reorder mode on.", visible: :all
    within(item("group_profiles", @bob, group: @everyone)) do
      assert_button "Move Bob up"
      assert_button "Move Bob down"
    end
    assert_text "Drag the handles or use the arrow buttons"

    click_button "Done reordering"
    assert_no_selector ".reorder-handle"
    assert_no_selector ".reorder-btn"
    assert_button "Reorder"
  end

  test "move buttons reorder a group's profiles, keep focus, announce and save" do
    click_button "Reorder"
    # Alphabetical to start with: Bob, then Everyone Profile
    assert_equal [ "Bob", "Everyone Profile" ], names_in("group_profiles", @everyone)

    within(item("group_profiles", @everyone_profile, group: @everyone)) { click_button "Move Everyone Profile up" }

    assert_equal [ "Everyone Profile", "Bob" ], names_in("group_profiles", @everyone)
    # It's now first, so focus moves to the button that can still do something
    assert_selector "#{item_selector('group_profiles', @everyone_profile, group: @everyone)} .reorder-btn--down:focus"
    assert_selector "#{item_selector('group_profiles', @everyone_profile, group: @everyone)} .reorder-btn--up[aria-disabled='true']"
    assert_selector "[data-sidebar-reorder-target='status']", text: "Everyone Profile moved to position 1 of 2 in Everyone.", visible: :all

    wait_for_saved { @everyone.ordered_profiles.map(&:name) == [ "Everyone Profile", "Bob" ] }

    # The public group page follows the new order
    visit group_path(@everyone.uuid)
    cards = all(".explorer__content .profile-grid .profile-card h3").map(&:text)
    assert_equal [ "Friends", "Everyone Profile", "Bob" ], cards
  end

  test "move buttons inside a group's row don't open or close the group" do
    partners = @user.groups.create!(name: "Partners")
    partners.group_profiles.create!(profile: @alice)
    visit our_profiles_path
    click_button "Reorder"

    within(item("groups", partners)) { click_button "Move Partners up" }

    assert_equal [ "Partners", "Everyone" ], top_level_names
    assert_selector "#{item_selector('groups', partners)} > details[open]"
    wait_for_saved { partners.reload.position == 0 }
  end

  test "dragging a handle reorders the list" do
    click_button "Reorder"
    assert_equal [ "Alice", "Bob" ], names_in("profiles").first(2)

    drag(item("profiles", @alice), below: item("profiles", @bob))

    assert_equal [ "Bob", "Alice" ], names_in("profiles").first(2)
    wait_for_saved { @user.profiles.order_by_position_then_name.first(2).map(&:name) == [ "Bob", "Alice" ] }
  end

  test "an item can't be dragged into another list" do
    click_button "Reorder"

    # A profile dragged over its group's child group stays among the profiles
    drag(item("group_profiles", @everyone_profile, group: @everyone), below: item("group_groups", @friends, group: @everyone), offset: -5)

    assert_equal [ "Friends" ], names_in("group_groups", @everyone)
    assert_equal [ "Bob", "Everyone Profile" ], names_in("group_profiles", @everyone)
  end

  test "reorder mode stays on across pages until it's switched off" do
    click_button "Reorder"
    assert_selector ".reorder-handle"

    visit our_groups_path
    assert_selector ".reorder-handle"
    assert_button "Done reordering"

    click_button "Done reordering"
    visit our_profiles_path
    assert_no_selector ".reorder-handle"
  end

  test "a list that changed elsewhere isn't saved, and goes back to how it was" do
    click_button "Reorder"
    # Another tab removes Bob from the group after this page loaded
    @everyone.group_profiles.find_by(profile: @bob).destroy!

    within(item("group_profiles", @everyone_profile, group: @everyone)) { click_button "Move Everyone Profile up" }

    assert_selector "[role='alert']", text: "This list has changed since the page loaded"
    assert_equal [ "Bob", "Everyone Profile" ], names_in("group_profiles", @everyone)
    # Putting the list back doesn't lose the keyboard user's place
    assert_selector "#{item_selector('group_profiles', @everyone_profile, group: @everyone)} .reorder-btn:focus"
  end

  test "when a save fails, moves queued behind it are dropped rather than saved" do
    click_button "Reorder"
    # The first save fails slowly, so the second move is queued behind it
    page.execute_script(<<~JS)
      const realFetch = window.fetch
      let calls = 0
      window.fetch = (...args) => {
        calls++
        if (calls === 1) return new Promise(resolve => setTimeout(() => resolve(new Response(null, { status: 500 })), 500))
        return realFetch(...args)
      }
    JS

    target = item_selector("profiles", profiles(:everyone_profile))
    find("#{target} .reorder-btn--up").click
    find("#{target} .reorder-btn--up").click

    assert_selector "[role='alert']", text: "Couldn't save the new order"
    assert_equal [ "Alice", "Bob", "Everyone Profile" ], names_in("profiles").first(3)
    sleep 0.5 # long enough for a wrongly queued save to land
    assert @user.profiles.reload.all? { |profile| profile.position.nil? }
    assert_selector "[role='alert']", text: "Couldn't save the new order"
  end

  test "Enter and Space on a group's move buttons move it without opening or closing it" do
    partners = @user.groups.create!(name: "Partners")
    partners.group_profiles.create!(profile: @alice)
    visit our_profiles_path
    click_button "Reorder"

    # A group's <li> holds its children's buttons too; its own come first
    find("#{item_selector('groups', partners)} .reorder-btn--up", match: :first).send_keys(:enter)
    assert_equal [ "Partners", "Everyone" ], top_level_names
    assert_selector "#{item_selector('groups', partners)} > details[open]"

    find("#{item_selector('groups', partners)} .reorder-btn--down", match: :first).send_keys(:space)
    assert_equal [ "Everyone", "Partners" ], top_level_names
    assert_selector "#{item_selector('groups', partners)} > details[open]"
    wait_for_saved { partners.reload.position == 1 }
  end

  test "a group shown in two places is reordered in both" do
    shared = @user.groups.create!(name: "Shared")
    shared.group_profiles.create!(profile: @alice)
    shared.group_profiles.create!(profile: @bob)
    @everyone.child_links.create!(child_group: shared)
    @friends.child_links.create!(child_group: shared)
    visit our_profiles_path
    click_button "Reorder"

    copies = all("li[data-reorder-list='group_groups'][data-reorder-id='#{shared.uuid}']")
    assert_equal 2, copies.size
    within(copies.first) do
      find(item_selector("group_profiles", @bob, group: shared)).find(".reorder-btn--up").click
    end

    copies.each do |copy|
      names = copy.all("li[data-reorder-list='group_profiles']").map { |node| node["data-reorder-name"] }
      assert_equal [ "Bob", "Alice" ], names
    end
    wait_for_saved { shared.ordered_profiles.map(&:name) == [ "Bob", "Alice" ] }
  end

  test "Sort A–Z puts a group's contents back in alphabetical order" do
    @everyone.group_profiles.find_by(profile: @everyone_profile).update!(position: 0)
    @everyone.group_profiles.find_by(profile: @bob).update!(position: 1)
    visit our_profiles_path
    click_button "Reorder"
    assert_equal [ "Everyone Profile", "Bob" ], names_in("group_profiles", @everyone)

    accept_confirm do
      within(item("groups", @everyone)) { click_button "Sort Everyone's contents A–Z" }
    end

    wait_for_saved { @everyone.group_profiles.reload.all? { |link| link.position.nil? } }
    # The page reloads in the new order, still in reorder mode
    assert_selector "#{item_selector('group_profiles', @bob, group: @everyone)} + #{item_selector('group_profiles', @everyone_profile, group: @everyone)}"
    assert_selector ".reorder-handle"
  end

  test "move buttons work in forced-colors mode, with the ends shown as unavailable" do
    click_button "Reorder"

    with_forced_colors do
      first_item = item_selector("group_profiles", @bob, group: @everyone)
      gray_text = system_color("GrayText")
      canvas_text = system_color("CanvasText")

      assert_equal gray_text, computed("#{first_item} .reorder-btn--up", "color")
      assert_equal canvas_text, computed("#{first_item} .reorder-btn--down", "color")
    end
  end

  private

  def item_selector(list, record, group: nil)
    selector = "li[data-reorder-list='#{list}'][data-reorder-id='#{record.uuid}']"
    selector += "[data-reorder-group='#{group.uuid}']" if group
    selector
  end

  def item(list, record, group: nil)
    find(item_selector(list, record, group: group), match: :first)
  end

  def names_in(list, group = nil)
    selector = "li[data-reorder-list='#{list}']"
    selector += "[data-reorder-group='#{group.uuid}']" if group
    all(selector).map { |node| node["data-reorder-name"] }.uniq
  end

  def top_level_names
    all("li[data-reorder-list='groups']").map { |node| node["data-reorder-name"] }
  end

  # SortableJS (in its pointer-event mode) follows the pointer across several
  # moves, so the drag goes in steps rather than one jump.
  def drag(source, below:, offset: 0)
    handle = source.find(".reorder-handle", match: :first)
    target_height = below.native.size.height
    page.driver.browser.action
        .click_and_hold(handle.native)
        .move_by(0, 4)
        .move_to(below.native)
        .move_by(0, (target_height / 2) - 4 + offset)
        .move_by(0, 2)
        .release
        .perform
  end

  # Saving happens in the background after the page has already changed
  def wait_for_saved(timeout: Capybara.default_max_wait_time)
    deadline = Time.current + timeout
    until yield
      flunk "the new order wasn't saved" if Time.current > deadline
      sleep 0.1
    end
  end

  def computed(selector, property)
    page.evaluate_script("getComputedStyle(document.querySelector(#{selector.to_json})).#{property}")
  end

  def system_color(name)
    page.evaluate_script(<<~JS)
      (() => {
        const probe = document.createElement("span")
        probe.style.color = #{name.to_json}
        document.body.appendChild(probe)
        const color = getComputedStyle(probe).color
        probe.remove()
        return color
      })()
    JS
  end
end
