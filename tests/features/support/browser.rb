# Real-browser acceptance coverage for localStorage and bookmark interactions.
require "selenium-webdriver"

Capybara.register_driver :bookmark_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--window-size=1440,1200")
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end
Capybara.javascript_driver = :bookmark_chrome
Capybara.enable_aria_label = true
Capybara.server = :puma, { Silent: true }

# A fresh browser profile isolates persistent bookmarks between scenarios and
# avoids Capybara 3's wildcard-origin cleanup, rejected by recent Chrome versions.
After("@javascript") do
  Capybara.current_session.driver.quit
end
