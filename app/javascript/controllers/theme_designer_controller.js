import { Controller } from "@hotwired/stimulus"

// Maps theme property names (underscore) to CSS custom property names (hyphen)
function cssProp(property) {
  return `--${property.replace(/_/g, "-")}`
}

export default class extends Controller {
  static targets = ["colorInput", "hexInput", "preview", "cssOutput", "copyLabel"]

  connect() {
    this.applyAllToPreview()
  }

  // Called when a colour picker changes
  updatePreview(event) {
    const input = event.currentTarget
    const property = input.dataset.property
    const value = input.value

    // Sync the hex text input
    const hexInput = this.hexInputTargets.find(el => el.dataset.property === property)
    if (hexInput) hexInput.value = value

    this.applyToPreview(property, value)
    this.updateCssOutput()
  }

  // Called when the hex text input changes
  updateFromHex(event) {
    const input = event.currentTarget
    const property = input.dataset.property
    let value = input.value.trim()

    // Auto-add # prefix
    if (value.length && value[0] !== "#") value = `#${value}`

    // Only apply if it looks like a valid hex colour
    if (/^#[0-9a-fA-F]{6}$/.test(value)) {
      const colorInput = this.colorInputTargets.find(el => el.dataset.property === property)
      if (colorInput) colorInput.value = value

      this.applyToPreview(property, value)
      this.updateCssOutput()
    }
  }

  // Apply a single property to the preview container
  applyToPreview(property, value) {
    if (!this.hasPreviewTarget) return
    this.previewTarget.style.setProperty(cssProp(property), value)

    // Also update computed properties that depend on text
    if (property === "text") {
      this.previewTarget.style.setProperty("--tree-guide", `color-mix(in srgb, ${value} 30%, transparent)`)
      this.previewTarget.style.setProperty("--avatar-placeholder-border", `color-mix(in srgb, ${value} 50%, transparent)`)
    }
  }

  // Apply all current colours to the preview
  applyAllToPreview() {
    this.colorInputTargets.forEach(input => {
      this.applyToPreview(input.dataset.property, input.value)
    })
  }

  // Regenerate the CSS output textarea
  updateCssOutput() {
    if (!this.hasCssOutputTarget) return

    const lines = this.colorInputTargets.map(input => {
      const prop = cssProp(input.dataset.property)
      return `  ${prop}: ${input.value};`
    })

    this.cssOutputTarget.value = `:root {\n${lines.join("\n")}\n}`
  }

  // Copy CSS to clipboard
  copyCss() {
    if (!this.hasCssOutputTarget) return

    navigator.clipboard.writeText(this.cssOutputTarget.value).then(() => {
      if (this.hasCopyLabelTarget) {
        const label = this.copyLabelTarget
        const original = label.textContent
        label.textContent = "Copied!"
        setTimeout(() => { label.textContent = original }, 2000)
      }
    }).catch(() => {
      if (this.hasCopyLabelTarget) {
        const label = this.copyLabelTarget
        const original = label.textContent
        label.textContent = "Copy failed"
        setTimeout(() => { label.textContent = original }, 2000)
      }
    })
  }

}
