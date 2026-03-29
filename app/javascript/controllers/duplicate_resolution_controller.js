import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submit"]

  connect() {
    this.submitTarget.disabled = true
  }

  choose() {
    this.submitTarget.disabled = false
  }
}
