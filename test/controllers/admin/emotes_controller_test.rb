require "test_helper"

class Admin::EmotesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:one)
    @member = users(:two)
    @emote = emotes(:cadbury_heart)
  end

  TURBO_STREAM = { "Accept" => "text/vnd.turbo-stream.html, text/html" }.freeze

  # -- Access --

  test "requires authentication" do
    get admin_emotes_path
    assert_redirected_to new_session_path
  end

  test "non-admins are redirected from every action" do
    sign_in_as @member

    get admin_emotes_path
    assert_redirected_to root_path
    patch admin_emote_path(@emote), params: { emote: { name: "hacked" } }
    assert_redirected_to root_path
    patch archive_admin_emote_path(@emote)
    assert_redirected_to root_path
    delete admin_emote_path(@emote)
    assert_redirected_to root_path

    assert_equal "48_cadbury_heart", @emote.reload.name
    assert_not @emote.archived?
  end

  # -- Index --

  test "index lists emotes by group in natural name order" do
    sign_in_as @admin
    get admin_emotes_path

    assert_response :success
    names = css_select("#emote-sections .emote-row input[name='emote[name]']").map { |input| input["value"] }
    assert_equal "01_dewdrop_heart", names.first
    assert_equal "50_sunshine_heart", names.last
    assert_select "summary.emote-section__heading", text: /Hearts/
  end

  test "index shows the derived code, disabled until overridden" do
    sign_in_as @admin
    get admin_emotes_path

    assert_select "##{ActionView::RecordIdentifier.dom_id(@emote, :code)}[value='cadbury_heart'][disabled]"
  end

  # -- Update --

  test "renaming re-renders the list and keeps the old code as an alias" do
    sign_in_as @admin
    patch admin_emote_path(@emote), params: { emote: { name: "48_chocolate_heart", code_overridden: "0" } }, headers: TURBO_STREAM

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match 'target="emote-sections"', response.body
    assert_match "Saved 48_chocolate_heart.", response.body
    assert_equal "chocolate_heart", @emote.reload.code
    assert_equal [ "cadbury_heart" ], @emote.aliases.pluck(:code)
  end

  test "a failed rename re-renders just that row with errors" do
    sign_in_as @admin
    patch admin_emote_path(@emote), params: { emote: { name: "36_red_heart", code_overridden: "0" } }, headers: TURBO_STREAM

    assert_response :success
    assert_match %(target="#{ActionView::RecordIdentifier.dom_id(@emote)}"), response.body
    assert_match "is already used by 36_red_heart", response.body
    assert_equal "48_cadbury_heart", @emote.reload.name
  end

  test "overriding the code keeps it through renames" do
    sign_in_as @admin
    patch admin_emote_path(@emote), params: { emote: { code_overridden: "1", code: "cadbury" } }, headers: TURBO_STREAM
    patch admin_emote_path(@emote), params: { emote: { name: "01_cadbury_heart", code_overridden: "1", code: "cadbury" } }, headers: TURBO_STREAM

    @emote.reload
    assert_equal "01_cadbury_heart", @emote.name
    assert_equal "cadbury", @emote.code
  end

  test "turning the override off re-derives the code, ignoring any sent code" do
    @emote.update!(code: "cadbury", code_overridden: true)
    sign_in_as @admin
    patch admin_emote_path(@emote), params: { emote: { code_overridden: "0", code: "ignored" } }, headers: TURBO_STREAM

    assert_equal "cadbury_heart", @emote.reload.code
  end

  test "moving an emote to another group" do
    other = EmoteGroup.create!(name: "Other", position: 1)
    sign_in_as @admin
    patch admin_emote_path(@emote), params: { emote: { emote_group_id: other.id } }, headers: TURBO_STREAM

    assert_equal other, @emote.reload.emote_group
  end

  test "an unknown group is ignored" do
    sign_in_as @admin
    patch admin_emote_path(@emote), params: { emote: { emote_group_id: 0 } }, headers: TURBO_STREAM

    assert_equal emote_groups(:hearts), @emote.reload.emote_group
  end

  test "html requests redirect back to the list" do
    sign_in_as @admin
    patch admin_emote_path(@emote), params: { emote: { name: "48_chocolate_heart" } }

    assert_redirected_to admin_emotes_path
    assert_equal "Saved 48_chocolate_heart.", flash[:notice]
  end

  # -- Archive, restore, delete --

  test "archive and restore" do
    sign_in_as @admin

    patch archive_admin_emote_path(@emote), headers: TURBO_STREAM
    assert @emote.reload.archived?

    patch restore_admin_emote_path(@emote), headers: TURBO_STREAM
    assert_not @emote.reload.archived?
  end

  test "an emote must be archived before it can be deleted" do
    sign_in_as @admin
    delete admin_emote_path(@emote)

    assert_redirected_to admin_emotes_path
    assert Emote.exists?(@emote.id)
  end

  test "deleting an archived emote removes it" do
    @emote.archive!
    sign_in_as @admin
    delete admin_emote_path(@emote), headers: TURBO_STREAM

    assert_response :success
    assert_not Emote.exists?(@emote.id)
    assert_nil EmoteRegistry.current.resolve("cadbury_heart")
  end

  # -- Aliases --

  test "removing an old code stops it resolving" do
    @emote.update!(name: "48_chocolate_heart")
    emote_alias = @emote.aliases.find_by!(code: "cadbury_heart")
    sign_in_as @admin
    delete remove_alias_admin_emote_path(@emote, alias_id: emote_alias.id), headers: TURBO_STREAM

    assert_response :success
    assert_empty @emote.aliases.reload
    assert_nil EmoteRegistry.current.resolve("cadbury_heart")
  end

  # -- Upload --

  def png_upload(filename)
    Rack::Test::UploadedFile.new(StringIO.new(png_bytes(8, 8)), "image/png", original_filename: filename)
  end

  test "non-admins can't upload" do
    sign_in_as @member

    get upload_admin_emotes_path
    assert_redirected_to root_path
    assert_no_difference -> { ActiveStorage::Blob.count } do
      post upload_admin_emotes_path, params: { files: [ png_upload("07_party.png") ] }
    end
    assert_redirected_to root_path
    post resolve_admin_emotes_path, params: { rows: { "0" => { signed_id: "x", name: "07_party", action: "create" } } }
    assert_redirected_to root_path
  end

  test "upload page offers the groups" do
    sign_in_as @admin
    get upload_admin_emotes_path

    assert_response :success
    assert_select "input[type=file][name='files[]'][multiple]"
    assert_select "select[name=emote_group_id] option", text: "Hearts"
  end

  test "uploading with no files sends the admin back" do
    sign_in_as @admin
    post upload_admin_emotes_path, params: { files: [ "" ] }

    assert_redirected_to upload_admin_emotes_path
    assert_equal "Choose at least one image to upload.", flash[:alert]
  end

  test "new files are added straight away, and rejected ones reported" do
    sign_in_as @admin
    post upload_admin_emotes_path, params: { emote_group_id: emote_groups(:hearts).id, files: [
      png_upload("07_party.png"), png_upload("100.png"),
      Rack::Test::UploadedFile.new(StringIO.new("hi"), "text/plain", original_filename: "notes.txt")
    ] }

    assert_redirected_to admin_emotes_path
    assert_equal "2 emotes added.", flash[:notice]
    assert_equal "Not uploaded: notes.txt isn't a PNG or WebP image.", flash[:alert]
    assert Emote.exists?(name: "07_party")
    assert Emote.exists?(code: "100")
  end

  test "a clash shows the decision page, and saving applies the decision" do
    sign_in_as @admin
    post upload_admin_emotes_path, params: { files: [ png_upload("07_party.png"), png_upload("36_red_heart.png") ] }

    assert_response :success
    assert_select "p", text: "1 emote added."
    assert_select ".upload-review__row", 1
    assert_select ".upload-review__heading", text: /36_red_heart.png\s+is named like an emote that already exists/
    assert_select "input[type=radio][name='rows[0][action]'][value=replace][checked]"

    signed_id = css_select("input[name='rows[0][signed_id]']").first["value"]
    post resolve_admin_emotes_path, params: { rows: { "0" => { signed_id: signed_id, name: "36_red_heart", action: "replace", replace_id: emotes(:red_heart).id } } }

    assert_redirected_to admin_emotes_path
    assert_equal "1 image replaced.", flash[:notice]
    assert_equal "36_red_heart.png", emotes(:red_heart).reload.image.filename.to_s
  end

  test "a failed decision re-renders the page with errors and saves nothing" do
    row = EmoteUpload.process([ png_upload("36_red_heart.png") ], group_id: nil).pending.first
    sign_in_as @admin
    post resolve_admin_emotes_path, params: { rows: { "0" => { signed_id: row.signed_id, name: "36_red_heart", action: "create" } } }

    assert_response :unprocessable_content
    assert_select ".flash--alert", text: /Nothing was saved/
    assert_select ".upload-review__errors", text: /already used by 36_red_heart/
    assert_select "input[name='rows[0][signed_id]'][value=?]", row.signed_id
  end

  test "decisions for expired or tampered files send the admin back to upload" do
    sign_in_as @admin
    post resolve_admin_emotes_path, params: { rows: { "0" => { signed_id: "tampered", name: "x", action: "create" } } }

    assert_redirected_to upload_admin_emotes_path
  end
end
