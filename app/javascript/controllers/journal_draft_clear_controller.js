import { Controller } from "@hotwired/stimulus"
import { clearDraft } from "journal_drafts"

// On the page after posting: the entry's on Dreamwidth now, so its draft
// goes.
export default class extends Controller {
  static values = { key: String }

  connect() {
    clearDraft(this.keyValue)
    this.element.remove()
  }
}
