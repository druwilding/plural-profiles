require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ] do |driver_option|
    driver_option.add_argument("--disable-search-engine-choice-screen")
    driver_option.add_preference("credentials_enable_service", false)
    driver_option.add_preference("profile.password_manager_leak_detection", false)
  end

  setup do
    Capybara.default_max_wait_time = 5
  end
end
