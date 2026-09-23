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
    assert_select "h3.emote-section__heading", text: /Hearts/
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
    other = EmoteGroup.create!(name: "Other", position: 1, plain_text: "★")
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
end
