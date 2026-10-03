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

  test "reorder mode adds a handle to each item, and Done takes them away" do
    assert_no_selector ".reorder-handle"
    start_reordering

    assert_selector ".sidebar--reordering"
    assert_selector "[data-sidebar-reorder-target='status']", text: "Reorder mode on.", visible: :all
    assert_text "Drag the handles to move things within their own list"
    within(item("group_profiles", @bob, group: @everyone)) do
      handle = find_button("Reorder Bob")
      assert_equal "Use the up and down arrow keys to move it.", handle_description(handle)
    end
    # Just the handles: no other buttons on the rows
    assert_no_selector "li[data-reorder-item] button:not(.reorder-handle)"

    finish_reordering
    assert_no_selector ".reorder-handle"
    assert_selector ".sidebar-reorder-toggle[aria-pressed='false']"
  end

  test "arrow keys on a handle reorder a group's profiles, keep focus, announce and save" do
    start_reordering
    # Alphabetical to start with: Bob, then Everyone Profile
    assert_equal [ "Bob", "Everyone Profile" ], names_in("group_profiles", @everyone)

    handle(item("group_profiles", @everyone_profile, group: @everyone)).send_keys(:up)

    assert_equal [ "Everyone Profile", "Bob" ], names_in("group_profiles", @everyone)
    assert_selector "#{item_selector('group_profiles', @everyone_profile, group: @everyone)} > .reorder-handle:focus"
    assert_selector "[data-sidebar-reorder-target='status']", text: "Everyone Profile moved to position 1 of 2 in Everyone.", visible: :all

    wait_for_saved { @everyone.ordered_profiles.map(&:name) == [ "Everyone Profile", "Bob" ] }

    # The public group page follows the new order
    visit group_path(@everyone.uuid)
    cards = all(".explorer__content .profile-grid .profile-card h3").map(&:text)
    assert_equal [ "Friends", "Everyone Profile", "Bob" ], cards
  end

  test "moving past the end of a list says so and saves nothing" do
    start_reordering

    handle(item("group_profiles", @bob, group: @everyone)).send_keys(:up)

    assert_selector "[data-sidebar-reorder-target='status']", text: "Bob is already first in Everyone.", visible: :all
    assert_equal [ "Bob", "Everyone Profile" ], names_in("group_profiles", @everyone)
    assert @everyone.group_profiles.reload.all? { |link| link.position.nil? }
  end

  test "a group's handle moves it with the keyboard without opening or closing it" do
    partners = @user.groups.create!(name: "Partners")
    partners.group_profiles.create!(profile: @alice)
    visit our_profiles_path
    start_reordering

    partners_handle = handle(item("groups", partners))
    partners_handle.send_keys(:enter)
    partners_handle.send_keys(:space)
    assert_selector "#{item_selector('groups', partners)} > details[open]"

    partners_handle.send_keys(:up)
    assert_equal [ "Partners", "Everyone" ], top_level_names
    assert_selector "#{item_selector('groups', partners)} > details[open]"
    wait_for_saved { partners.reload.position == 0 }
  end

  test "dragging a handle reorders the list" do
    start_reordering
    assert_equal [ "Alice", "Bob" ], names_in("profiles").first(2)

    drag(item("profiles", @alice), below: item("profiles", @bob))

    assert_equal [ "Bob", "Alice" ], names_in("profiles").first(2)
    wait_for_saved { @user.profiles.order_by_position_then_name.first(2).map(&:name) == [ "Bob", "Alice" ] }
  end

  test "an item can't be dragged into another list" do
    start_reordering

    # A profile dragged over its group's child group stays among the profiles
    drag(item("group_profiles", @everyone_profile, group: @everyone), below: item("group_groups", @friends, group: @everyone), offset: -5)

    assert_equal [ "Friends" ], names_in("group_groups", @everyone)
    assert_equal [ "Bob", "Everyone Profile" ], names_in("group_profiles", @everyone)
  end

  test "reorder mode stays on across pages until it's switched off" do
    start_reordering
    assert_selector ".reorder-handle"

    visit our_groups_path
    assert_selector ".reorder-handle"
    assert_selector ".sidebar-reorder-toggle[aria-pressed='true']"

    finish_reordering
    visit our_profiles_path
    assert_no_selector ".reorder-handle"
  end

  test "a list that changed elsewhere isn't saved, and goes back to how it was" do
    start_reordering
    # Another tab removes Bob from the group after this page loaded
    @everyone.group_profiles.find_by(profile: @bob).destroy!

    handle(item("group_profiles", @everyone_profile, group: @everyone)).send_keys(:up)

    assert_selector "[role='alert']", text: "This list has changed since the page loaded"
    assert_equal [ "Bob", "Everyone Profile" ], names_in("group_profiles", @everyone)
    # Putting the list back doesn't lose the keyboard user's place
    assert_selector "#{item_selector('group_profiles', @everyone_profile, group: @everyone)} > .reorder-handle:focus"
  end

  test "a list reordered in another tab isn't overwritten" do
    start_reordering
    # Another tab puts Everyone Profile first after this page loaded
    @everyone.group_profiles.find_by(profile: @everyone_profile).update!(position: 0)
    @everyone.group_profiles.find_by(profile: @bob).update!(position: 1)

    handle(item("group_profiles", @bob, group: @everyone)).send_keys(:down)

    assert_selector "[role='alert']", text: "This list has changed since the page loaded"
    assert_equal [ "Bob", "Everyone Profile" ], names_in("group_profiles", @everyone)
    assert_equal [ "Everyone Profile", "Bob" ], @everyone.ordered_profiles.map(&:name)
  end

  test "moves made one after another in the same tab aren't mistaken for another tab's" do
    start_reordering
    bob_handle = handle(item("group_profiles", @bob, group: @everyone))

    bob_handle.send_keys(:down)
    wait_for_saved { @everyone.ordered_profiles.map(&:name) == [ "Everyone Profile", "Bob" ] }
    bob_handle.send_keys(:up)
    wait_for_saved { @everyone.ordered_profiles.map(&:name) == [ "Bob", "Everyone Profile" ] }
    assert_selector "[role='alert']", text: "", visible: :all, exact_text: true
  end

  test "moves after switching reorder mode off and on again aren't mistaken for another tab's" do
    start_reordering
    handle(item("group_profiles", @bob, group: @everyone)).send_keys(:down)
    wait_for_saved { @everyone.ordered_profiles.map(&:name) == [ "Everyone Profile", "Bob" ] }

    finish_reordering
    start_reordering
    handle(item("group_profiles", @bob, group: @everyone)).send_keys(:up)

    wait_for_saved { @everyone.ordered_profiles.map(&:name) == [ "Bob", "Everyone Profile" ] }
    assert_selector "[role='alert']", text: "", visible: :all, exact_text: true
  end

  test "a save after being signed out says so, and puts the list back" do
    start_reordering
    Session.where(user: @user).delete_all

    handle(item("group_profiles", @everyone_profile, group: @everyone)).send_keys(:up)

    assert_selector "[role='alert']", text: "You've been signed out"
    assert_equal [ "Bob", "Everyone Profile" ], names_in("group_profiles", @everyone)
  end

  test "when a save fails, moves queued behind it are dropped rather than saved" do
    start_reordering
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

    everyone_profile_handle = handle(item("profiles", @everyone_profile))
    everyone_profile_handle.send_keys(:up)
    everyone_profile_handle.send_keys(:up)

    assert_selector "[role='alert']", text: "Couldn't save the new order"
    assert_equal [ "Alice", "Bob", "Everyone Profile" ], names_in("profiles").first(3)
    sleep 0.5 # long enough for a wrongly queued save to land
    assert @user.profiles.reload.all? { |profile| profile.position.nil? }
    assert_selector "[role='alert']", text: "Couldn't save the new order"
  end

  test "a group shown in two places is reordered in both" do
    shared = @user.groups.create!(name: "Shared")
    shared.group_profiles.create!(profile: @alice)
    shared.group_profiles.create!(profile: @bob)
    @everyone.child_links.create!(child_group: shared)
    @friends.child_links.create!(child_group: shared)
    visit our_profiles_path
    start_reordering

    copies = all("li[data-reorder-list='group_groups'][data-reorder-id='#{shared.uuid}']")
    assert_equal 2, copies.size
    handle(copies.first.find(item_selector("group_profiles", @bob, group: shared))).send_keys(:up)

    copies.each do |copy|
      names = copy.all("li[data-reorder-list='group_profiles']").map { |node| node["data-reorder-name"] }
      assert_equal [ "Bob", "Alice" ], names
    end
    wait_for_saved { shared.ordered_profiles.map(&:name) == [ "Bob", "Alice" ] }
  end

  test "Sort A–Z puts the profiles list back in alphabetical order" do
    @bob.update!(position: 0)
    @alice.update!(position: 1)
    visit our_profiles_path
    assert_no_button "Sort A–Z" # only while reordering
    start_reordering
    assert_equal [ "Bob", "Alice" ], names_in("profiles").first(2)

    accept_confirm do
      find("button[data-reorder-reset='profiles']", text: "Sort A–Z").click
    end

    wait_for_saved { @user.profiles.reload.all? { |profile| profile.position.nil? } }
    # The page reloads in the new order, still in reorder mode
    assert_selector "#{item_selector('profiles', @alice)} + #{item_selector('profiles', @bob)}"
    assert_selector ".reorder-handle"
  end

  test "handles are visible in forced-colors mode" do
    start_reordering

    with_forced_colors do
      selector = "#{item_selector('group_profiles', @bob, group: @everyone)} > .reorder-handle"
      assert_equal system_color("CanvasText"), computed(selector, "color")
      assert_equal system_color("Canvas"), computed(selector, "backgroundColor")
    end
  end

  test "the toggle is a round button beside the hide button, showing a tick while reordering" do
    toggle = find("button.sidebar-reorder-toggle", text: "Reorder groups and profiles")
    assert_equal "false", toggle["aria-pressed"]
    assert_equal "Reorder groups and profiles", toggle["title"]
    assert_selector ".sidebar-reorder-toggle__start", visible: true
    assert_no_selector ".sidebar-reorder-toggle__done", visible: true

    hide_top = find("button.sidebar-toggle--hide").native.rect.y
    assert_in_delta hide_top, toggle.native.rect.y, 1

    start_reordering
    assert_equal "Done reordering", toggle["title"]
    assert_selector ".sidebar-reorder-toggle__done", visible: true
    assert_no_selector ".sidebar-reorder-toggle__start", visible: true
  end

  private

  def start_reordering
    find("button.sidebar-reorder-toggle[aria-pressed='false']").click
    assert_selector ".sidebar-reorder-toggle[aria-pressed='true']"
  end

  def finish_reordering
    find("button.sidebar-reorder-toggle[aria-pressed='true']").click
    assert_selector ".sidebar-reorder-toggle[aria-pressed='false']"
  end

  def item_selector(list, record, group: nil)
    selector = "li[data-reorder-list='#{list}'][data-reorder-id='#{record.uuid}']"
    selector += "[data-reorder-group='#{group.uuid}']" if group
    selector
  end

  def item(list, record, group: nil)
    find(item_selector(list, record, group: group), match: :first)
  end

  # A group's <li> holds its children's handles too; its own comes first
  def handle(item)
    item.find(".reorder-handle", match: :first)
  end

  def handle_description(handle)
    page.evaluate_script("document.getElementById(#{handle['aria-describedby'].to_json}).textContent").strip
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
    target_height = below.native.size.height
    page.driver.browser.action
        .click_and_hold(handle(source).native)
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
