import { Controller } from "@hotwired/stimulus"

// Handles the "Import theme" dialog on the themes index.
// Parses a pasted JSON theme export (or legacy CSS :root { } block) and
// redirects to the new-theme page with values pre-populated as query params.
export default class extends Controller {
  static targets = ["dialog", "cssInput", "error"]
  static values  = { newUrl: String }

  open() {
    this.dialogTarget.showModal()
    this.cssInputTarget.focus()
  }

  close() {
    this.dialogTarget.close()
    this.clearError()
  }

  // Close when clicking the backdrop (outside the dialog box)
  backdropClick(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }

  import(event) {
    event.preventDefault()
    const input = this.cssInputTarget.value.trim()

    // Try JSON first
    if (input.startsWith("{")) {
      this.importJson(input)
    } else {
      // Fallback: try legacy CSS format
      this.importCss(input)
    }
  }

  importJson(input) {
    try {
      const data = JSON.parse(input)
      if (!data.plural_profiles_theme) {
        this.showError(
          "This doesn't look like a Plural Profiles theme. " +
          "Make sure you paste the full JSON export."
        )
        return
      }

      const params = new URLSearchParams()
      if (data.name) params.append("theme[name]", data.name)
      if (data.colors && typeof data.colors === "object") {
        for (const [key, value] of Object.entries(data.colors)) {
          params.append(`theme[colors][${key}]`, value)
        }
      }
      if (Array.isArray(data.tags)) {
        data.tags.forEach(tag => params.append("theme[tags][]", tag))
      }
      if (data.credit) params.append("theme[credit]", data.credit)
      if (data.credit_url) params.append("theme[credit_url]", data.credit_url)
      if (data.notes) params.append("theme[notes]", data.notes)
      if (data.background_repeat) params.append("theme[background_repeat]", data.background_repeat)
      if (data.background_size) params.append("theme[background_size]", data.background_size)
      if (data.background_position) params.append("theme[background_position]", data.background_position)
      if (data.background_attachment) params.append("theme[background_attachment]", data.background_attachment)

      window.location.href = `${this.newUrlValue}?${params.toString()}`
    } catch (e) {
      this.showError("Invalid JSON. Make sure you paste the full export.")
    }
  }

  importCss(input) {
    const colors = this.parseCss(input)

    if (Object.keys(colors).length === 0) {
      this.showError(
        "No valid theme data found. " +
        "Paste either a JSON theme export or a CSS :root { } block."
      )
      return
    }

    const params = new URLSearchParams()
    for (const [key, value] of Object.entries(colors)) {
      params.append(`theme[colors][${key}]`, value)
    }

    window.location.href = `${this.newUrlValue}?${params.toString()}`
  }

  // Parse --custom-property: #hex pairs, convert hyphens → underscores for model keys
  parseCss(css) {
    const result = {}
    const re = /--([a-z][a-z0-9-]*)\s*:\s*(#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?)\s*;/g
    let m
    while ((m = re.exec(css)) !== null) {
      const key = m[1].replace(/-/g, "_")
      result[key] = m[2]
    }
    return result
  }

  showError(message) {
    this.errorTarget.textContent = message
  }

  clearError() {
    this.errorTarget.textContent = ""
  }
}
