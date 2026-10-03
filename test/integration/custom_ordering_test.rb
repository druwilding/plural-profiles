require "test_helper"

# The custom order reaches the rendered pages, not just the model queries.
# Custom and alphabetical order disagree in every list here.
class CustomOrderingIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @household = @user.groups.create!(name: "Household", position: 0)
    @alpha     = @user.groups.create!(name: "Alpha team")
    @zeta      = @user.groups.create!(name: "Zeta team")
    GroupGroup.create!(parent_group: @household, child_group: @zeta, position: 0)
    GroupGroup.create!(parent_group: @household, child_group: @alpha, position: 1)

    @ash  = @user.profiles.create!(name: "Ash")
    @wren = @user.profiles.create!(name: "Wren", position: 0)
    GroupProfile.create!(group: @household, profile: @wren, position: 0)
    GroupProfile.create!(group: @household, profile: @ash, position: 1)
    GroupProfile.create!(group: @zeta, profile: @ash, position: 0)
    GroupProfile.create!(group: @zeta, profile: @wren, position: 1)

    sign_in_as @user
  end

  test "public group page shows cards and tree in the group's order" do
    get group_path(@household.uuid)
    assert_response :success

    assert_equal [ "Zeta team", "Alpha team", "Wren", "Ash" ], card_names(".explorer__content")
    # Repeated profiles carry visually hidden "(already listed elsewhere…)" text
    tree_labels = css_select("#group-sidebar .tree__label").map { |node| node.text.strip.lines.first.strip }
    assert_equal [ "Household", "Zeta team", "Ash", "Wren", "Alpha team", "Wren", "Ash" ], tree_labels
  end

  test "public panel for a nested group uses that group's order" do
    get panel_group_path(@zeta.uuid, root: @household.uuid, path: [ @zeta.id ])
    assert_response :success
    assert_equal [ "Ash", "Wren" ], card_names
  end

  test "our group page shows cards in the group's order" do
    get our_group_path(@household)
    assert_response :success
    assert_equal [ "Zeta team", "Alpha team", "Wren", "Ash" ], card_names(".profile-grid")
  end

  test "our profiles index uses the account-wide order" do
    get our_profiles_path
    assert_response :success
    names = card_names(".profile-grid")
    assert_operator names.index("Wren"), :<, names.index("Alice")
    assert_operator names.index("Alice"), :<, names.index("Ash")
  end

  test "sidebar shows the household group in its order" do
    get our_groups_path
    assert_response :success

    household = css_select(".sidebar-tree__folder").find { |node| node.at_css(".sidebar-tree__label")&.text&.strip == "Household" }
    labels = household.css(".sidebar-tree__children > li > .sidebar-tree__link .sidebar-tree__label, .sidebar-tree__children > li > details > summary .sidebar-tree__label")
                      .map { |node| node.text.strip }
    assert_equal [ "Zeta team", "Ash", "Wren", "Alpha team", "Wren", "Ash" ], labels
  end

  private

  def card_names(scope = "")
    css_select("#{scope} .profile-card h3".strip).map { |node| node.text.strip }
  end
end
