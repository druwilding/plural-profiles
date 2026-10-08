import { Controller } from "@hotwired/stimulus"
import { clearDraftsForUser } from "journal_drafts"

// Signing out clears the account's journal drafts, so unposted writing
// doesn't stay behind in a shared browser (as chat drafts do).
export default class extends Controller {
  static values = { user: String }

  clearDrafts() {
    clearDraftsForUser(this.userValue)
  }
}
