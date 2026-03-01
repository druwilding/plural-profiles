import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "profilesToggle"]

  connect() {
    this._previousMode = this._currentMode()
    this.updateCheckboxes()
  }

  change(event) {
    const el = event.target
    if (!el || el.name !== 'inclusion_mode') return
    this.updateCheckboxes()
    this._previousMode = this._currentMode()
  }

  updateCheckboxes() {
    const mode = this._currentMode()
    if (!mode) return

    this.checkboxTargets.forEach(cb => {
      if (mode === 'all') { cb.checked = true; cb.disabled = true }
      else if (mode === 'none') { cb.checked = false; cb.disabled = true }
      else if (mode === 'selected') { cb.disabled = false }
    })

    if (this.hasProfilesToggleTarget) {
      const toggle = this.profilesToggleTarget
      // When switching TO selected from another mode, uncheck; when switching TO all, check
      if (mode === 'selected' && this._previousMode !== 'selected') {
        toggle.checked = false
      } else if (mode === 'all' && this._previousMode !== 'all') {
        toggle.checked = true
      }
      // Always leave the toggle editable
    }
  }

  _currentMode() {
    const selected = this.element.querySelector('input[name="inclusion_mode"]:checked')
    return selected ? selected.value : null
  }
}
