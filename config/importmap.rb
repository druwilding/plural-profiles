# Pin npm packages by running ./bin/importmap

pin "application"
pin "chat_drafts"
pin "journal_drafts"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "@melloware/coloris", to: "@melloware--coloris.js" # @0.25.0
pin "sortablejs" # @1.15.7
