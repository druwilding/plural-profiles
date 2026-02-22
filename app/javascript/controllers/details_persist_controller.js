import { Controller } from "@hotwired/stimulus"

// Persists the open/closed state of <details> elements using localStorage.
// Usage: <details data-controller="details-persist" data-details-persist-key-value="my-key">
export default class extends Controller {
  static values = { key: String }

  connect() {
    const stored = localStorage.getItem(this.storageKey)
    if (stored === "closed") {
      this.element.removeAttribute("open")
    } else if (stored === "open") {
      this.element.setAttribute("open", "")
    }

    this.element.addEventListener("toggle", this.persist)
  }

  disconnect() {
    this.element.removeEventListener("toggle", this.persist)
  }

  persist = () => {
    localStorage.setItem(this.storageKey, this.element.open ? "open" : "closed")
  }

  get storageKey() {
    return `details-persist:${this.keyValue}`
  }
}
