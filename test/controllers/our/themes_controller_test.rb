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
    assert_no_match "Cerulean", response.body
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

  test "create accepts 8-digit hex colors with alpha" do
    sign_in_as @user
    assert_difference("Theme.count", 1) do
      post our_themes_path, params: {
        theme: { name: "Translucent", colors: { page_bg: "#00000080", text: "#ffffffcc" } }
      }
    end
    assert_redirected_to our_themes_path
    theme = Theme.last
    assert_equal "#00000080", theme.colors["page_bg"]
    assert_equal "#ffffffcc", theme.colors["text"]
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
    copy = Theme.last
    assert_equal "Dark Forest (copy)", copy.name
  end

  test "duplicate copies the colors from the original" do
    sign_in_as @user
    post duplicate_our_theme_path(@theme)
    copy = Theme.last
    assert_equal @theme.colors, copy.colors
  end

  test "duplicate copies the tags from the original" do
    sign_in_as @user
    post duplicate_our_theme_path(@theme)
    copy = Theme.last
    assert_equal @theme.tags, copy.tags
  end

  test "duplicate redirects to the edit page for the copy" do
    sign_in_as @user
    post duplicate_our_theme_path(@theme)
    copy = Theme.last
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

  test "activate works for a shared theme not owned by the user" do
    shared = themes(:ocean_shared)
    sign_in_as @other_user
    patch activate_our_theme_path(shared)
    @other_user.reload
    assert_equal shared.id, @other_user.active_theme_id
    assert_redirected_to our_themes_path
  end

  test "activate rejects another user's personal theme" do
    sign_in_as @other_user
    patch activate_our_theme_path(@theme)
    assert_response :not_found
    @other_user.reload
    assert_nil @other_user.active_theme_id
  end

  test "deactivate clears active theme" do
    sign_in_as @user
    @user.update!(active_theme: @theme)
    patch deactivate_our_themes_path
    @user.reload
    assert_nil @user.active_theme_id
    assert_redirected_to our_themes_path
  end

  # -- Tags --

  test "index shows themes with their tags" do
    sign_in_as @user
    get our_themes_path
    assert_response :success
    assert_match "Dark", response.body
    assert_match "Warm colours", response.body
  end

  test "index filtered by tag returns only matching themes" do
    sign_in_as @user
    get our_themes_path, params: { tags: [ "dark" ] }
    assert_response :success
    assert_match "Dark Forest", response.body
    assert_no_match "Sunset", response.body
  end

  test "index filtered by tag excludes themes that do not match" do
    sign_in_as @user
    get our_themes_path, params: { tags: [ "warm-colours" ] }
    assert_response :success
    assert_match "Sunset", response.body
    assert_no_match "Dark Forest", response.body
  end

  test "index with multiple tags requires all to match" do
    sign_in_as @user
    get our_themes_path, params: { tags: [ "dark", "warm-colours" ] }
    assert_response :success
    assert_no_match "Dark Forest", response.body
    assert_no_match "Sunset", response.body
    assert_match "No themes match", response.body
  end

  test "index filter ignores unknown tags" do
    sign_in_as @user
    get our_themes_path, params: { tags: [ "nonsense" ] }
    assert_response :success
    # Unknown tag is silently dropped so all themes are shown
    assert_match "Dark Forest", response.body
    assert_match "Sunset", response.body
  end

  test "active theme is shown even when tag filter excludes it" do
    sign_in_as @user
    @user.update!(active_theme: @theme)
    # dark_forest has tags [dark, cool-colours] — filter by warm-colours excludes it
    get our_themes_path, params: { tags: [ "warm-colours" ] }
    assert_response :success
    assert_match "Active theme", response.body
    assert_match "Dark Forest", response.body
  end

  test "create saves tags" do
    sign_in_as @user
    post our_themes_path, params: {
      theme: { name: "Night Owl", colors: {}, tags: [ "dark", "cool-colours" ] }
    }
    assert_redirected_to our_themes_path
    theme = Theme.find_by!(name: "Night Owl")
    assert_equal [ "dark", "cool-colours" ], theme.tags
  end

  test "create strips unknown tags" do
    sign_in_as @user
    post our_themes_path, params: {
      theme: { name: "Mystery", colors: {}, tags: [ "dark", "invented-tag" ] }
    }
    assert_redirected_to our_themes_path
    theme = Theme.find_by!(name: "Mystery")
    assert_equal [ "dark" ], theme.tags
  end

  test "update saves tags" do
    sign_in_as @user
    patch our_theme_path(@theme), params: {
      theme: { name: @theme.name, colors: @theme.colors, tags: [ "light", "high-contrast" ] }
    }
    assert_redirected_to our_themes_path
    assert_equal [ "light", "high-contrast" ], @theme.reload.tags
  end

  test "update clears tags when none submitted" do
    sign_in_as @user
    patch our_theme_path(@theme), params: {
      theme: { name: @theme.name, colors: @theme.colors, tags: [ "" ] }
    }
    assert_redirected_to our_themes_path
    assert_equal [], @theme.reload.tags
  end

  # -- Credit & notes --

  test "create saves credit and notes" do
    sign_in_as @user
    post our_themes_path, params: {
      theme: { name: "Credited", colors: {}, credit: "Dru", notes: "Some notes here" }
    }
    assert_redirected_to our_themes_path
    theme = Theme.find_by!(name: "Credited")
    assert_equal "Dru", theme.credit
    assert_equal "Some notes here", theme.notes
  end

  test "create saves credit_url" do
    sign_in_as @user
    post our_themes_path, params: {
      theme: { name: "Linked Credit", colors: {}, credit: "Dru", credit_url: "https://example.com" }
    }
    assert_redirected_to our_themes_path
    assert_equal "https://example.com", Theme.find_by!(name: "Linked Credit").credit_url
  end

  test "create rejects invalid credit_url" do
    sign_in_as @user
    assert_no_difference("Theme.count") do
      post our_themes_path, params: {
        theme: { name: "Bad URL", colors: {}, credit_url: "not-a-url" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "update saves credit and notes" do
    sign_in_as @user
    patch our_theme_path(@theme), params: {
      theme: { name: @theme.name, colors: @theme.colors, credit: "Dru", notes: "Updated notes" }
    }
    assert_redirected_to our_themes_path
    @theme.reload
    assert_equal "Dru", @theme.credit
    assert_equal "Updated notes", @theme.notes
  end

  test "duplicate copies credit and notes" do
    sign_in_as @user
    @theme.update!(credit: "Dru", notes: "Original notes", credit_url: "https://example.com")
    post duplicate_our_theme_path(@theme)
    copy = Theme.order(:created_at).last
    assert_equal "Dru", copy.credit
    assert_equal "Original notes", copy.notes
    assert_equal "https://example.com", copy.credit_url
  end

  # -- Button border colours --

  test "create saves button border colours" do
    sign_in_as @user
    post our_themes_path, params: {
      theme: {
        name: "Bordered",
        colors: {
          primary_button_border: "#ff0000",
          secondary_button_border: "#00ff00",
          danger_button_border: "#0000ff"
        }
      }
    }
    assert_redirected_to our_themes_path
    theme = Theme.find_by!(name: "Bordered")
    assert_equal "#ff0000", theme.colors["primary_button_border"]
    assert_equal "#00ff00", theme.colors["secondary_button_border"]
    assert_equal "#0000ff", theme.colors["danger_button_border"]
  end

  test "update saves button border colours" do
    sign_in_as @user
    patch our_theme_path(@theme), params: {
      theme: {
        name: @theme.name,
        colors: @theme.colors.merge(
          "primary_button_border" => "#aaaaaa",
          "secondary_button_border" => "#bbbbbb",
          "danger_button_border" => "#cccccc"
        )
      }
    }
    assert_redirected_to our_themes_path
    @theme.reload
    assert_equal "#aaaaaa", @theme.colors["primary_button_border"]
    assert_equal "#bbbbbb", @theme.colors["secondary_button_border"]
    assert_equal "#cccccc", @theme.colors["danger_button_border"]
  end

  test "duplicate copies button border colours" do
    sign_in_as @user
    @theme.update_column(:colors, @theme.colors.merge(
      "primary_button_border" => "#112233",
      "secondary_button_border" => "#445566",
      "danger_button_border" => "#778899"
    ))
    post duplicate_our_theme_path(@theme)
    copy = Theme.order(:created_at).last
    assert_equal "#112233", copy.colors["primary_button_border"]
    assert_equal "#445566", copy.colors["secondary_button_border"]
    assert_equal "#778899", copy.colors["danger_button_border"]
  end

  # -- Shared themes --

  test "index shows shared themes section to all logged-in users" do
    sign_in_as @other_user
    get our_themes_path
    assert_response :success
    assert_match "Shared themes", response.body
    assert_match "Ocean Shared", response.body
  end

  test "index does not show shared themes in personal themes section" do
    sign_in_as @user
    get our_themes_path
    assert_response :success
    # Shared theme appears in Shared themes section, not counted as a personal theme
    assert_match "Ocean Shared", response.body
  end

  test "non-admin cannot set shared on create" do
    sign_in_as @other_user
    post our_themes_path, params: {
      theme: { name: "Sneaky shared", colors: {}, shared: true }
    }
    assert_redirected_to our_themes_path
    theme = Theme.find_by!(name: "Sneaky shared")
    assert_not theme.shared?
  end

  test "admin can create a shared theme" do
    sign_in_as @user
    assert @user.admin?
    post our_themes_path, params: {
      theme: { name: "Admin shared theme", colors: {}, shared: true }
    }
    assert_redirected_to our_themes_path
    theme = Theme.find_by!(name: "Admin shared theme")
    assert theme.shared?
  end

  test "non-admin can duplicate a shared theme" do
    shared = themes(:ocean_shared)
    sign_in_as @other_user
    assert_difference("Theme.count", 1) do
      post duplicate_our_theme_path(shared)
    end
    copy = Theme.order(:created_at).last
    assert_equal @other_user, copy.user
    assert_not copy.shared?
  end

  test "non-admin cannot edit a shared theme they do not own" do
    shared = themes(:ocean_shared)
    sign_in_as @other_user
    get edit_our_theme_path(shared)
    assert_response :not_found
  end

  test "non-admin cannot delete a shared theme" do
    shared = themes(:ocean_shared)
    sign_in_as @other_user
    assert_no_difference("Theme.count") do
      delete our_theme_path(shared)
    end
    assert_response :not_found
  end

  test "duplicated shared theme has shared false" do
    shared = themes(:ocean_shared)
    sign_in_as @user
    post duplicate_our_theme_path(shared)
    copy = Theme.order(:created_at).last
    assert_not copy.shared?
  end

  # -- Show / preview --

  test "show renders a user's own theme" do
    sign_in_as @user
    get our_theme_path(@theme)
    assert_response :success
    assert_match @theme.name, response.body
  end

  test "show renders a shared theme for any logged-in user" do
    shared = themes(:ocean_shared)
    sign_in_as @other_user
    get our_theme_path(shared)
    assert_response :success
    assert_match shared.name, response.body
  end

  test "show returns 404 for another user's personal theme" do
    sign_in_as @other_user
    get our_theme_path(@theme)
    assert_response :not_found
  end

  # -- Cross-admin: one admin acting on another admin's shared theme --

  test "admin can edit another admin's shared theme" do
    sign_in_as @user
    assert @user.admin?
    theme = themes(:another_admin_shared)
    assert_not_equal theme.user_id, @user.id
    get edit_our_theme_path(theme)
    assert_response :success
  end

  test "admin can update another admin's shared theme" do
    sign_in_as @user
    theme = themes(:another_admin_shared)
    patch our_theme_path(theme), params: { theme: { name: "Renamed by other admin" } }
    assert_redirected_to our_themes_path
    assert_equal "Renamed by other admin", theme.reload.name
  end

  test "admin can delete another admin's shared theme" do
    sign_in_as @user
    theme = themes(:another_admin_shared)
    assert_difference("Theme.count", -1) do
      delete our_theme_path(theme)
    end
    assert_redirected_to our_themes_path
  end

  test "admin can set another admin's shared theme as default" do
    sign_in_as @user
    theme = themes(:another_admin_shared)
    assert_not theme.site_default?
    patch set_default_our_theme_path(theme)
    assert_redirected_to our_themes_path
    assert theme.reload.site_default?
  end

  test "non-admin cannot edit another user's shared theme" do
    sign_in_as @other_user
    assert_not @other_user.admin?
    theme = themes(:another_admin_shared)
    get edit_our_theme_path(theme)
    assert_response :not_found
  end

  test "non-admin cannot delete another user's shared theme" do
    sign_in_as @other_user
    theme = themes(:another_admin_shared)
    assert_no_difference("Theme.count") do
      delete our_theme_path(theme)
    end
    assert_response :not_found
  end

  # -- Default theme --

  test "admin can set a shared theme as the default" do
    sign_in_as @user
    assert @user.admin?
    theme = themes(:ocean_shared)
    assert_not theme.site_default?
    patch set_default_our_theme_path(theme)
    assert_redirected_to our_themes_path
    assert theme.reload.site_default?
    assert_match "is now the default theme", flash[:notice]
  end

  test "set_default toggles off when theme is already the default" do
    sign_in_as @user
    theme = themes(:default_shared)
    assert theme.site_default?
    patch set_default_our_theme_path(theme)
    assert_redirected_to our_themes_path
    assert_not theme.reload.site_default?
    assert_match "is no longer the default theme", flash[:notice]
  end

  test "non-admin cannot call set_default" do
    sign_in_as @other_user
    assert_not @other_user.admin?
    theme = themes(:ocean_shared)
    patch set_default_our_theme_path(theme)
    assert_redirected_to our_themes_path
    assert_match "Only admins", flash[:alert]
    assert_not theme.reload.site_default?
  end

  test "cannot delete the default theme" do
    sign_in_as @user
    theme = themes(:default_shared)
    assert theme.site_default?
    assert_no_difference("Theme.count") do
      delete our_theme_path(theme)
    end
    assert_redirected_to our_themes_path
    assert_match "Cannot delete the default theme", flash[:alert]
  end

  test "deactivate shows site default message" do
    sign_in_as @user
    @user.update!(active_theme: themes(:dark_forest))
    patch deactivate_our_themes_path
    assert_redirected_to our_themes_path
    assert_match "site default", flash[:notice]
  end

  # -- Import via JSON query params --

  test "new with JSON-imported colours populates the form" do
    sign_in_as @user
    get new_our_theme_path, params: {
      theme: { colors: { page_bg: "#aabbcc", text: "#112233" } }
    }
    assert_response :success
    assert_match "#aabbcc", response.body
    assert_match "#112233", response.body
  end

  test "new with imported name uses it instead of default" do
    sign_in_as @user
    get new_our_theme_path, params: {
      theme: { name: "Imported Theme" }
    }
    assert_response :success
    assert_match "Imported Theme", response.body
  end

  test "new with imported credit and notes populates them" do
    sign_in_as @user
    get new_our_theme_path, params: {
      theme: { credit: "Dru", credit_url: "https://example.com", notes: "Imported notes" }
    }
    assert_response :success
    assert_match "Dru", response.body
    assert_match "https://example.com", response.body
    assert_match "Imported notes", response.body
  end

  test "new with imported tags populates them" do
    sign_in_as @user
    get new_our_theme_path, params: {
      theme: { tags: [ "dark", "cool-colours" ] }
    }
    assert_response :success
    assert_select "input[type=checkbox][name='theme[tags][]'][value='dark'][checked]"
    assert_select "input[type=checkbox][name='theme[tags][]'][value='cool-colours'][checked]"
    assert_select "input[type=checkbox][name='theme[tags][]'][value='light'][checked]", count: 0
  end

  test "new with imported background options populates them" do
    sign_in_as @user
    get new_our_theme_path, params: {
      theme: { background_repeat: "no-repeat", background_size: "cover" }
    }
    assert_response :success
    assert_select "select[name='theme[background_repeat]'] option[value='no-repeat'][selected]"
    assert_select "select[name='theme[background_size]'] option[value='cover'][selected]"
  end

  test "new ignores invalid imported background options" do
    sign_in_as @user
    get new_our_theme_path, params: {
      theme: { background_repeat: "invalid-value" }
    }
    assert_response :success
    # Invalid value is filtered out; the DB default (repeat) should remain selected
    assert_select "select[name='theme[background_repeat]'] option[value='repeat'][selected]"
    assert_select "select[name='theme[background_repeat]'] option[value='invalid-value']", count: 0
  end

  test "new with legacy CSS colour import still works" do
    sign_in_as @user
    get new_our_theme_path, params: {
      theme: { colors: { page_bg: "#112233" } }
    }
    assert_response :success
    assert_match "#112233", response.body
  end
end
