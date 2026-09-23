import { Controller } from "@hotwired/stimulus"

// Submits its form as soon as a field changes (on blur, or straight away for
// selects and checkboxes), so a list of small forms can be edited without
// Save buttons. Enter submits immediately too.
//
// Enter followed by blur would otherwise send the same change twice, so a
// submit is skipped when nothing has changed since the last one.
export default class extends Controller {
  connect() {
    this.lastSubmitted = this.serialize()
  }

  submit() {
    const current = this.serialize()
    if (current === this.lastSubmitted) return

    this.lastSubmitted = current
    this.element.requestSubmit()
  }

  submitNow(event) {
    if (event.target.tagName !== "INPUT") return

    event.preventDefault()
    this.submit()
  }

  serialize() {
    return new URLSearchParams(new FormData(this.element)).toString()
  }
}
