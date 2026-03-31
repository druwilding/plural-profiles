require "application_system_test_case"

class ThemeBackgroundImageTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @theme = themes(:sunset)
    sign_in_via_browser
  end

  teardown do
    @theme.background_image.purge if @theme.background_image.attached?
  end

  # -- Uploading a background image --

  test "uploading a background image updates the preview immediately" do
    visit edit_our_theme_path(@theme)

    find("summary", text: "Background image").click
    attach_file "theme[background_image]", file_fixture("avatar.png").to_path

    # Stimulus applies the image to the preview element (wait for it)
    assert_selector ".theme-preview[style*='background-image']"
  end

  test "background image thumbnail and remove checkbox appear when an image is attached" do
    @theme.background_image.attach(
      io: file_fixture("avatar.png").open,
      filename: "avatar.png",
      content_type: "image/png"
    )

    visit edit_our_theme_path(@theme)
    find("summary", text: "Background image").click

    assert_css "img.theme-bg-preview"
    assert_text "Remove background image"
  end

  # -- Removing a background image --

  test "can remove a background image via the remove checkbox" do
    @theme.background_image.attach(
      io: file_fixture("avatar.png").open,
      filename: "avatar.png",
      content_type: "image/png"
    )

    visit edit_our_theme_path(@theme)
    find("summary", text: "Background image").click

    assert_css "img.theme-bg-preview"

    check "Remove background image"
    click_button "Save theme"

    assert_text "Theme saved."

    visit edit_our_theme_path(@theme)
    assert_current_path edit_our_theme_path(@theme)
    find("summary", text: "Background image").click

    # Wait for the section to fully render (not a Turbo snapshot) before
    # asserting absence — the upload label is always present when there's no image.
    assert_text "JPG, PNG, or WebP"

    assert_no_css "img.theme-bg-preview"
    assert_no_text "Remove background image"
  end

  # -- Background image in body style --

  test "background image appears in body style when theme with image is active" do
    @theme.background_image.attach(
      io: file_fixture("avatar.png").open,
      filename: "avatar.png",
      content_type: "image/png"
    )
    @user.update!(active_theme: @theme)

    visit our_themes_path

    assert_match(/background-image:\s*url\(/, find("body")[:style])
  end

  test "background image is not in body style when theme has no image" do
    @user.update!(active_theme: @theme)

    visit our_themes_path

    refute_match(/background-image/, find("body")[:style].to_s)
  end

  # -- Live preview of background options --

  test "changing repeat select updates the preview style immediately" do
    visit edit_our_theme_path(@theme)
    find("summary", text: "Background image").click

    select "no-repeat", from: "Repeat"

    assert_match(/background-repeat:\s*no-repeat/, find(".theme-preview")[:style])
  end

  test "changing size select updates the preview style immediately" do
    visit edit_our_theme_path(@theme)
    find("summary", text: "Background image").click

    select "Cover", from: "Size"

    assert_match(/background-size:\s*cover/, find(".theme-preview")[:style])
  end

  test "changing position select updates the preview style immediately" do
    visit edit_our_theme_path(@theme)
    find("summary", text: "Background image").click

    select "Top", from: "Position"

    assert_match(/background-position:[^;]*\btop\b/, find(".theme-preview")[:style])
  end

  test "changing attachment select updates the preview style immediately" do
    visit edit_our_theme_path(@theme)
    find("summary", text: "Background image").click

    select "Fixed (stays in place)", from: "Scroll behaviour"

    assert_match(/background-attachment:\s*fixed/, find(".theme-preview")[:style])
  end

  # -- Persistence of background options --

  test "background options are saved and restored correctly" do
    visit edit_our_theme_path(@theme)
    find("summary", text: "Background image").click

    select "no-repeat", from: "Repeat"
    select "Cover", from: "Size"
    select "Top", from: "Position"
    select "Fixed (stays in place)", from: "Scroll behaviour"

    click_button "Save theme"
    assert_text "Theme saved."

    @theme.reload
    assert_equal "no-repeat", @theme.background_repeat
    assert_equal "cover", @theme.background_size
    assert_equal "top", @theme.background_position
    assert_equal "fixed", @theme.background_attachment
  end

  test "background options appear in body style when theme with image is active" do
    @theme.background_image.attach(
      io: file_fixture("avatar.png").open,
      filename: "avatar.png",
      content_type: "image/png"
    )
    @theme.update!(
      background_repeat: "no-repeat",
      background_size: "cover",
      background_position: "top",
      background_attachment: "fixed"
    )
    @user.update!(active_theme: @theme)

    visit our_themes_path

    body_style = find("body")[:style]
    assert_match(/background-repeat:\s*no-repeat/, body_style)
    assert_match(/background-size:\s*cover/, body_style)
    assert_match(/background-position:[^;]*\btop\b/, body_style)
    assert_match(/background-attachment:\s*fixed/, body_style)
  end
end
