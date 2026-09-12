require "test_helper"

require "minitest/reporters"
Minitest::Reporters.use!(
  [
    Minitest::Reporters::DefaultReporter.new(color: true),
    Minitest::Reporters::HtmlReporter.new(reports_dir: "test/reports", output_filename: "system-test-report.html")
  ],
  ENV,
  Minitest.backtrace_filter
)

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

  # Chrome's DevTools Protocol occasionally raises this exact, unclassified
  # error when Capybara tries to resolve a node reference at the moment a
  # Turbo Drive navigation swaps the document out from under it (typically
  # right after submitting a form, while polling an `assert_text`/`choose`
  # on the page it navigates to). It's genuinely transient — the same call
  # against the now-settled page always succeeds — but Capybara only
  # auto-retries a fixed list of recognized "stale element" exception
  # classes (see Capybara::Selenium::Driver#invalid_element_errors), and
  # Selenium::WebDriver::Error::UnknownError isn't one of them, so this
  # specific CDP inspector error otherwise surfaces as a hard failure.
  STALE_CDP_NODE_ERROR = /Node with given id does not belong to the document/

  def retrying_stale_cdp_node
    yield
  rescue Selenium::WebDriver::Error::UnknownError => e
    raise unless e.message.match?(STALE_CDP_NODE_ERROR)
    yield
  end

  # Wrap Capybara session methods to inject a pause between actions and to
  # retry once on the transient stale-node CDP error described above.
  %i[visit click_link click_button fill_in choose check uncheck].each do |method_name|
    define_method(method_name) do |*args, **kwargs, &block|
      sleep(@slowmo) if @slowmo
      retrying_stale_cdp_node { super(*args, **kwargs, &block) }
    end
  end

  # Same retry for the wait-based assertions used right after navigations.
  %i[assert_text assert_no_text assert_selector assert_no_selector].each do |method_name|
    define_method(method_name) do |*args, **kwargs, &block|
      retrying_stale_cdp_node { super(*args, **kwargs, &block) }
    end
  end

  def sign_in_via_browser(user = nil)
    user ||= @user
    visit new_session_path
    fill_in "Email address or account name", with: user.email_address
    fill_in "Password", with: "Plur4l!Pr0files#2026"
    click_button "Sign in"
    assert_current_path root_path
  end
end
