require "test_helper"

class Our::ThemesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @theme = themes(:dark_forest)
    @other_user = users(:two)
    @other_theme = themes(:other_user_theme)
  end

  # -- Authentication --

  test "index requires authentication" do
    get our_themes_path
    assert_redirected_to new_session_path
  end

  # -- Index --

  test "index lists current user themes" do
    sign_in_as @user
    get our_themes_path
    assert_response :success
    assert_match "Dark Forest", response.body
    assert_match "Sunset", response.body
    assert_no_match "Ocean", response.body
  end

  # -- New --

  test "new renders form" do
    sign_in_as @user
    get new_our_theme_path
    assert_response :success
  end

  # -- Create --

  test "create saves a valid theme" do
    sign_in_as @user
    assert_difference("Theme.count", 1) do
      post our_themes_path, params: {
        theme: { name: "Midnight", colors: { page_bg: "#000000", text: "#ffffff" } }
      }
    end
    assert_redirected_to our_themes_path
  end

  test "create rejects blank name" do
    sign_in_as @user
    assert_no_difference("Theme.count") do
      post our_themes_path, params: {
        theme: { name: "", colors: { page_bg: "#000000" } }
      }
    end
    assert_response :unprocessable_entity
  end

  # -- Edit --

  test "edit renders form for own theme" do
    sign_in_as @user
    get edit_our_theme_path(@theme)
    assert_response :success
    assert_match "Dark Forest", response.body
  end

  test "edit rejects other users theme" do
    sign_in_as @user
    get edit_our_theme_path(@other_theme)
    assert_response :not_found
  end

  # -- Update --

  test "update saves changes" do
    sign_in_as @user
    patch our_theme_path(@theme), params: {
      theme: { name: "Dark Forest v2", colors: { page_bg: "#111111" } }
    }
    assert_redirected_to our_themes_path
    @theme.reload
    assert_equal "Dark Forest v2", @theme.name
    assert_equal "#111111", @theme.colors["page_bg"]
  end

  # -- Destroy --

  test "destroy deletes theme" do
    sign_in_as @user
    assert_difference("Theme.count", -1) do
      delete our_theme_path(@theme)
    end
    assert_redirected_to our_themes_path
  end

  test "destroy clears active theme if it was active" do
    sign_in_as @user
    @user.update!(active_theme: @theme)
    delete our_theme_path(@theme)
    @user.reload
    assert_nil @user.active_theme_id
  end

  # -- Duplicate --

  test "duplicate creates a new theme with (copy) suffix" do
    sign_in_as @user
    assert_difference("Theme.count", 1) do
      post duplicate_our_theme_path(@theme)
    end
    copy = Theme.order(:created_at).last
    assert_equal "Dark Forest (copy)", copy.name
  end

  test "duplicate copies the colors from the original" do
    sign_in_as @user
    post duplicate_our_theme_path(@theme)
    copy = Theme.order(:created_at).last
    assert_equal @theme.colors, copy.colors
  end

  test "duplicate redirects to the edit page for the copy" do
    sign_in_as @user
    post duplicate_our_theme_path(@theme)
    copy = Theme.order(:created_at).last
    assert_redirected_to edit_our_theme_path(copy)
  end

  test "duplicate rejects another users theme" do
    sign_in_as @user
    assert_no_difference("Theme.count") do
      post duplicate_our_theme_path(@other_theme)
    end
    assert_response :not_found
  end

  # -- Activate / Deactivate --

  test "activate sets active theme" do
    sign_in_as @user
    patch activate_our_theme_path(@theme)
    @user.reload
    assert_equal @theme.id, @user.active_theme_id
    assert_redirected_to our_themes_path
  end

  test "deactivate clears active theme" do
    sign_in_as @user
    @user.update!(active_theme: @theme)
    patch deactivate_our_themes_path
    @user.reload
    assert_nil @user.active_theme_id
    assert_redirected_to our_themes_path
  end
end
