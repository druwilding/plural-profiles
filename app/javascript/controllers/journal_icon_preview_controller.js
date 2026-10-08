import { Controller } from "@hotwired/stimulus"

// Shows the chosen icon on the journal's Write page as soon as it's picked.
// Each option carries its icon's image address (data-url). Icons load from
// Dreamwidth, which can take a moment, so a spinner shows over the old icon
// until the new one arrives. Without JavaScript the page still works; the
// image just shows the icon from the last time the form was sent.
export default class extends Controller {
  static targets = [ "select", "image", "box", "spinner" ]

  update() {
    const url = this.selectTarget.selectedOptions[0]?.dataset.url

    if (!url) {
      // "(default)" before we know which icon that is: no image rather than
      // the wrong one.
      this.loaded()
      this.imageTarget.removeAttribute("src")
      this.imageTarget.hidden = true
      return
    }

    if (this.imageTarget.getAttribute("src") === url && !this.imageTarget.hidden) return

    this.imageTarget.hidden = false
    this.imageTarget.src = url
    // Already in the browser's cache: no wait, so no spinner.
    if (this.imageTarget.complete) {
      this.loaded()
    } else {
      this.boxTarget.classList.add("journal-details__icon--loading")
      this.spinnerTarget.hidden = false
    }
  }

  // The image finished loading, or failed to; either way, stop waiting.
  loaded() {
    this.boxTarget.classList.remove("journal-details__icon--loading")
    this.spinnerTarget.hidden = true
  }
}
