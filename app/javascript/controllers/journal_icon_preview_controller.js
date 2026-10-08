import { Controller } from "@hotwired/stimulus"

// Shows the chosen icon on the journal's Write page as soon as it's picked.
// Each option carries its icon's image address (data-url). Without
// JavaScript the page still works; the image just shows the icon from the
// last time the form was sent.
export default class extends Controller {
  static targets = [ "select", "image" ]

  update() {
    const url = this.selectTarget.selectedOptions[0]?.dataset.url

    if (url) {
      this.imageTarget.src = url
      this.imageTarget.hidden = false
    } else {
      // "(default)" before we know which icon that is: no image rather than
      // the wrong one.
      this.imageTarget.removeAttribute("src")
      this.imageTarget.hidden = true
    }
  }
}
