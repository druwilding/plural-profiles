import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox"]

  change(event) {
    const el = event.target
    if (!el || el.name !== 'inclusion_mode') return
    const mode = el.value
    this.checkboxTargets.forEach(cb => {
      if (mode === 'all') cb.checked = true
      else if (mode === 'none') cb.checked = false
      // if 'selected' do nothing
    })
  }
}
