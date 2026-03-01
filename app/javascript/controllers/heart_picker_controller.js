import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "input"]

  toggle(event) {
    const button = event.currentTarget
    const heart = button.dataset.heart
    const selected = button.getAttribute("aria-pressed") === "true"

    button.setAttribute("aria-pressed", !selected)

    this.syncInputs()
  }

  syncInputs() {
    // Remove existing hidden inputs
    this.inputTargets.forEach(input => input.remove())

    // Create new hidden inputs for each selected heart
    const selected = this.buttonTargets.filter(
      btn => btn.getAttribute("aria-pressed") === "true"
    )

    if (selected.length === 0) {
      // Send an empty value so Rails clears the array
      const emptyInput = document.createElement("input")
      emptyInput.type = "hidden"
      emptyInput.name = "profile[heart_emojis][]"
      emptyInput.value = ""
      emptyInput.dataset.heartPickerTarget = "input"
      this.element.appendChild(emptyInput)
    } else {
      selected.forEach(btn => {
        const input = document.createElement("input")
        input.type = "hidden"
        input.name = "profile[heart_emojis][]"
        input.value = btn.dataset.heart
        input.dataset.heartPickerTarget = "input"
        this.element.appendChild(input)
      })
    }
  }
}
