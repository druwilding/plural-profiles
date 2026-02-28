import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox"]

  connect() {
    this.updateCheckboxes()
  }

  change(event) {
    const el = event.target
    if (!el || el.name !== 'inclusion_mode') return
    this.updateCheckboxes()
  }

  updateCheckboxes() {
    const selected = this.element.querySelector('input[name="inclusion_mode"]:checked')
    if (!selected) return
    const mode = selected.value
    this.checkboxTargets.forEach(cb => {
      if (mode === 'all') { cb.checked = true; cb.disabled = true }
      else if (mode === 'none') { cb.checked = false; cb.disabled = true }
      else if (mode === 'selected') { cb.disabled = false }
    })
  }
}
