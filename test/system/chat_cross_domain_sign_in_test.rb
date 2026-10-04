require "application_system_test_case"

# Opening a chat page while signed out bounces to the sign-in page on the
# main domain (SessionsController#redirect_to_main_domain), which then sends
# the user back to the chat page once signed in. That redirect crosses from
# the main domain to chat.*, which a Turbo form submission (fetch) can't
# follow without CORS, so the sign-in form has to be a real form submission.
class ChatCrossDomainSignInTest < ApplicationSystemTestCase
  setup do
    @port = Capybara.current_session.server.port
    Capybara.app_host = "http://lvh.me:#{@port}"
    @user = users(:one)
    @server = @user.owned_chat_servers.create!(name: "Return Server")
    @server.memberships.create!(user: @user, role: "owner", default_postable: profiles(:alice))
  end

  teardown do
    Capybara.app_host = nil
  end

  test "signing in after being sent from a chat page goes back to that chat page" do
    visit "http://chat.lvh.me:#{@port}/servers/#{@server.uuid}"
    assert_current_path new_session_path

    sign_in_on_page(@user, "Plur4l!Pr0files#2026")

    assert_current_path "/servers/#{@server.uuid}"
    assert_equal "chat.lvh.me", URI(current_url).host
    assert_text "Return Server"
  end

  test "a wrong password from a chat page still says so" do
    visit "http://chat.lvh.me:#{@port}/servers/#{@server.uuid}"
    assert_current_path new_session_path

    sign_in_on_page(@user, "not the password")

    assert_current_path new_session_path
    assert_text "Try another email address or password."
  end

  private

  def sign_in_on_page(user, password)
    fill_in "Email address or account name", with: user.email_address
    fill_in "Password", with: password
    click_button "Sign in"
  end
end
