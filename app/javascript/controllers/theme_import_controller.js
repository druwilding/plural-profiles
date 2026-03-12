import { Controller } from "@hotwired/stimulus"

// Handles the "Import theme" dialog on the themes index.
// Parses a pasted :root { --prop: #hex; } block and redirects to the
// new-theme page with colour values pre-populated as query params.
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
    const css    = this.cssInputTarget.value.trim()
    const colors = this.parseCss(css)

    if (Object.keys(colors).length === 0) {
      this.showError(
        "No valid CSS custom properties found. " +
        "Make sure you paste a :root { } block containing --property: #rrggbb values."
      )
      return
    }

    // Build query string: theme[colors][page_bg]=#482784 etc.
    const params = new URLSearchParams()
    for (const [key, value] of Object.entries(colors)) {
      params.append(`theme[colors][${key}]`, value)
    }

    window.location.href = `${this.newUrlValue}?${params.toString()}`
  }

  // Parse --custom-property: #hex pairs, convert hyphens → underscores for model keys
  parseCss(css) {
    const result = {}
    const re = /--([a-z][a-z0-9-]*)\s*:\s*(#[0-9a-fA-F]{6})\s*;/g
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
