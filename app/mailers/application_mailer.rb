class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "noreply@pluralprofiles.com")
  layout "mailer"
end
