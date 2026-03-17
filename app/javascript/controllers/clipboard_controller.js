import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "label"]

  copy() {
    if (!this.hasSourceTarget) return

    const text = this.sourceTarget.value
    const originalLabel = this.hasLabelTarget ? this.labelTarget.textContent : null

    navigator.clipboard.writeText(text).then(() => {
      this.showFeedback("Copied!", originalLabel)
    }).catch(() => {
      this.showFeedback("Copy failed", originalLabel)
    })
  }

  showFeedback(message, originalLabel) {
    if (!this.hasLabelTarget) return

    this.labelTarget.textContent = message
    setTimeout(() => {
      this.labelTarget.textContent = originalLabel
    }, 2000)
  }
}
