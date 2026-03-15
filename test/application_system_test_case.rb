require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  browser = ENV["HEADLESS"] == "false" ? :chrome : :headless_chrome

  driven_by :selenium, using: browser, screen_size: [ 1400, 900 ] do |driver_option|
    driver_option.add_argument("--disable-search-engine-choice-screen")
    driver_option.add_preference("credentials_enable_service", false)
    driver_option.add_preference("profile.password_manager_leak_detection", false)
  end

  setup do
    Capybara.default_max_wait_time = 5

    if ENV["SLOWMO"]
      @slowmo = Float(ENV["SLOWMO"]) rescue 0.5
    end
  end

  teardown do
    if @slowmo
      sleep(@slowmo) # pause at the end so you can see the final state
      @slowmo = nil
    end
  end

  # Wrap Capybara session methods to inject a pause between actions
  %i[visit click_link click_button fill_in].each do |method_name|
    define_method(method_name) do |*args, **kwargs, &block|
      sleep(@slowmo) if @slowmo
      super(*args, **kwargs, &block)
    end
  end

  def sign_in_via_browser(user = nil)
    user ||= @user
    visit new_session_path
    fill_in "Email address", with: user.email_address
    fill_in "Password", with: "Plur4l!Pr0files#2026"
    click_button "Sign in"
    assert_current_path root_path
  end
end
