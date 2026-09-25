require "application_system_test_case"

class AdminEmoteUploadTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @dir = Dir.mktmpdir
    sign_in_via_browser
  end

  teardown do
    FileUtils.remove_entry(@dir)
  end

  def file(name, contents)
    path = File.join(@dir, name)
    File.binwrite(path, contents)
    path
  end

  test "PNG and SVG files are added straight away, with SVGs converted to PNG in the browser" do
    png = file("07-party.png", png_bytes(8, 8))
    svg = file("100.svg", %(<svg xmlns="http://www.w3.org/2000/svg" width="10" height="20"><rect width="10" height="20" fill="red"/></svg>))

    visit upload_admin_emotes_path
    attach_file "Images", [ png, svg ]
    assert_selector ".emote-upload__status", text: "SVGs were converted to PNG"
    click_button "Upload"

    assert_selector ".flash--notice", text: "2 emotes added."
    hundred = Emote.find_by!(code: "100")
    assert_equal "image/png", hundred.image.content_type
    assert_equal "100.png", hundred.image.filename.to_s
    assert_equal [ 128, 256 ], hundred.image.blob.open { |f| Vips::Image.new_from_file(f.path).size }
  end

  test "a clash asks what to do, and a new name adds it as a new emote" do
    visit upload_admin_emotes_path
    attach_file "Images", [ file("36-red-heart.png", png_bytes(8, 8)) ]
    click_button "Upload"

    assert_selector "h1", text: "Choose what to do"
    assert_checked_field "Give 36-red-heart this image instead"
    fill_in "Name", with: "02-spring-heart"
    assert_checked_field "Add it as a new emote"
    assert_text "“02-spring-heart” is already used by 02-spring-heart."
    fill_in "Name", with: "37-rouge-heart"
    assert_text "It will be typed as :rouge-heart:"
    click_button "Save"

    assert_selector ".flash--notice", text: "1 emote added."
    assert Emote.exists?(code: "rouge-heart")
  end

  test "uploading opens the group the emotes went into" do
    visit admin_emotes_path
    find("summary", text: "Hearts").click
    assert_selector "details.emote-section:not([open])", text: "Hearts"

    visit upload_admin_emotes_path
    attach_file "Images", [ file("07-party.png", png_bytes(8, 8)) ]
    click_button "Upload"

    assert_selector ".flash--notice", text: "1 emote added."
    assert_selector "details.emote-section[open]", text: "Hearts"
    assert_field with: "07-party"

    # It stays open, as if it had been opened by hand.
    visit admin_emotes_path
    assert_selector "details.emote-section[open]", text: "Hearts"
  end
end
