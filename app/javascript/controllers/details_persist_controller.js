import { Controller } from "@hotwired/stimulus"

// Persists the open/closed state of <details> elements using localStorage.
// Usage: <details data-controller="details-persist" data-details-persist-key-value="my-key">
// Set data-details-persist-force-open-value="true" to open it (and remember
// that) regardless of what was stored, e.g. after something was added to it.
// Toggles aren't remembered while data-open-before-filter is set, since a
// filter opened or closed it for the moment.
export default class extends Controller {
  static values = { key: String, forceOpen: Boolean }

  connect() {
    if (this.forceOpenValue) {
      this.element.setAttribute("open", "")
      localStorage.setItem(this.storageKey, "open")
      // Don't force it open again when Turbo restores this page from its cache.
      this.forceOpenValue = false
    } else {
      const stored = localStorage.getItem(this.storageKey)
      if (stored === "closed") {
        this.element.removeAttribute("open")
      } else if (stored === "open") {
        this.element.setAttribute("open", "")
      }
    }

    this.element.addEventListener("toggle", this.persist)
  }

  disconnect() {
    this.element.removeEventListener("toggle", this.persist)
  }

  persist = () => {
    if ("openBeforeFilter" in this.element.dataset) return
    localStorage.setItem(this.storageKey, this.element.open ? "open" : "closed")
  }

  get storageKey() {
    return `details-persist:${this.keyValue}`
  }
}
