import { Controller } from "@hotwired/stimulus"

// Toggles spoiler text visibility on click.
// Connects automatically to any element with data-controller="spoiler".
export default class extends Controller {
  toggle(event) {
    const span = event.target.closest(".spoiler")
    if (span) {
      span.classList.toggle("spoiler--revealed")
    }
  }
}
