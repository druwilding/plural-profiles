import { Controller } from "@hotwired/stimulus"

// Maps theme property names (underscore) to CSS custom property names (hyphen)
function cssProp(property) {
  return `--${property.replace(/_/g, "-")}`
}

// Convert Safari's color(srgb ...) format to #RRGGBBAA hex
function colorToHex(colorString) {
  // Check if it's already in hex format
  if (colorString.startsWith("#")) return colorString

  // Parse Safari's color(srgb R G B / A) format
  const match = colorString.match(/color\(srgb\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)(?:\s*\/\s*([\d.]+))?\)/i)
  if (match) {
    const r = Math.round(parseFloat(match[1]) * 255)
    const g = Math.round(parseFloat(match[2]) * 255)
    const b = Math.round(parseFloat(match[3]) * 255)
    const a = match[4] ? Math.round(parseFloat(match[4]) * 255) : 255

    const toHex = (n) => n.toString(16).padStart(2, "0")
    return `#${toHex(r)}${toHex(g)}${toHex(b)}${toHex(a)}`
  }

  // Fallback: return as-is
  return colorString
}

export default class extends Controller {
  static targets = ["colorInput", "hexInput", "preview", "cssOutput"]

  connect() {
    this.applyAllToPreview()
  }

  // Called when a colour picker changes
  updatePreview(event) {
    const input = event.currentTarget
    const property = input.dataset.property
    let value = input.value

    // Convert Safari's color(srgb ...) format to hex
    const hexValue = colorToHex(value)

    // Sync the hex text input
    const hexInput = this.hexInputTargets.find(el => el.dataset.property === property)
    if (hexInput) hexInput.value = hexValue

    this.applyToPreview(property, hexValue)
    this.updateCssOutput()
  }

  // Called when the hex text input changes
  updateFromHex(event) {
    const input = event.currentTarget
    const property = input.dataset.property
    let value = input.value.trim()

    // Auto-add # prefix
    if (value.length && value[0] !== "#") value = `#${value}`

    // Only apply if it looks like a valid hex colour (6 or 8 digits for alpha)
    if (/^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(value)) {
      // For 6-digit hex (no alpha), sync the color picker
      if (value.length === 7) {
        const colorInput = this.colorInputTargets.find(el => el.dataset.property === property)
        if (colorInput) colorInput.value = value
      }
      // For 8-digit hex (with alpha), native color input doesn't support it, so skip syncing

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
    this.hexInputTargets.forEach(input => {
      this.applyToPreview(input.dataset.property, input.value)
    })
  }

  // Regenerate the CSS output textarea
  updateCssOutput() {
    if (!this.hasCssOutputTarget) return

    const lines = this.hexInputTargets.map(input => {
      const prop = cssProp(input.dataset.property)
      return `  ${prop}: ${input.value};`
    })

    this.cssOutputTarget.value = `:root {\n${lines.join("\n")}\n}`
  }

}
