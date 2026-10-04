import { Controller } from "@hotwired/stimulus"
import { clearDraftsForUser } from "chat_drafts"

// The chat's "Sign out" button. Clears the account's unsent drafts on the
// way out, so they don't stay behind in a shared browser.
export default class extends Controller {
  static values = { user: String }

  clearDrafts() {
    clearDraftsForUser(this.userValue)
  }
}
