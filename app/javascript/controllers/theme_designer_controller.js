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
  static targets = ["colorInput", "hexInput", "preview", "jsonOutput",
                    "nameInput", "creditInput", "creditUrlInput", "notesInput", "tagInput",
                    "backgroundFileInput", "backgroundRepeat",
                    "backgroundSize", "backgroundPosition", "backgroundAttachment"]

  // Derived-text mix percentages, populated from Theme::DERIVED_TEXT_PROPERTIES
  // via a data attribute so the Ruby and JS definitions stay in sync.
  static values = { derivedTextProperties: Object }

  connect() {
    this.bgObjectUrl = null
    this.applyAllToPreview()
    this.applyBackgroundToPreview()
  }

  disconnect() {
    if (this.bgObjectUrl) URL.revokeObjectURL(this.bgObjectUrl)
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
    this.updateJsonOutput()
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
      this.updateJsonOutput()
    }
  }

  // Apply a single property to the preview container
  applyToPreview(property, value) {
    if (!this.hasPreviewTarget) return
    this.previewTarget.style.setProperty(cssProp(property), value)

    // Also update computed properties that depend on text.
    // Percentages come from the server via derivedTextPropertiesValue so they
    // stay in sync with Theme::DERIVED_TEXT_PROPERTIES without duplication.
    if (property === "text") {
      const derived = this.hasDerivedTextPropertiesValue ? this.derivedTextPropertiesValue : {}
      Object.entries(derived).forEach(([prop, percent]) => {
        this.previewTarget.style.setProperty(`--${prop}`, `color-mix(in srgb, ${value} ${percent}%, transparent)`)
      })
    }
  }

  // Apply all current colours to the preview
  applyAllToPreview() {
    this.hexInputTargets.forEach(input => {
      this.applyToPreview(input.dataset.property, input.value)
    })
  }

  // Regenerate the JSON export textarea with all current form values
  updateJsonOutput() {
    if (!this.hasJsonOutputTarget) return

    const data = { plural_profiles_theme: 1 }

    if (this.hasNameInputTarget && this.nameInputTarget.value.trim()) {
      data.name = this.nameInputTarget.value.trim()
    }

    const colors = {}
    this.hexInputTargets.forEach(input => {
      colors[input.dataset.property] = input.value
    })
    if (Object.keys(colors).length) data.colors = colors

    const tags = this.tagInputTargets
      .filter(cb => cb.checked && cb.value !== "")
      .map(cb => cb.value)
    if (tags.length) data.tags = tags

    if (this.hasCreditInputTarget && this.creditInputTarget.value.trim()) {
      data.credit = this.creditInputTarget.value.trim()
    }
    if (this.hasCreditUrlInputTarget && this.creditUrlInputTarget.value.trim()) {
      data.credit_url = this.creditUrlInputTarget.value.trim()
    }
    if (this.hasNotesInputTarget && this.notesInputTarget.value.trim()) {
      data.notes = this.notesInputTarget.value.trim()
    }

    if (this.hasBackgroundRepeatTarget) data.background_repeat = this.backgroundRepeatTarget.value
    if (this.hasBackgroundSizeTarget) data.background_size = this.backgroundSizeTarget.value
    if (this.hasBackgroundPositionTarget) data.background_position = this.backgroundPositionTarget.value
    if (this.hasBackgroundAttachmentTarget) data.background_attachment = this.backgroundAttachmentTarget.value

    this.jsonOutputTarget.value = JSON.stringify(data, null, 2)
  }

  // Called when user selects a new background image file
  previewBackgroundImage(event) {
    const file = event.target.files[0]
    if (!file) return
    if (this.bgObjectUrl) URL.revokeObjectURL(this.bgObjectUrl)
    this.bgObjectUrl = URL.createObjectURL(file)
    this.applyBackgroundToPreview()
  }

  // Called when any background option select changes
  updateBackgroundPreview() {
    this.applyBackgroundToPreview()
  }

  applyBackgroundToPreview() {
    if (!this.hasPreviewTarget) return
    const url = this.bgObjectUrl || this.previewTarget.dataset.existingBgUrl
    if (url) {
      this.previewTarget.style.backgroundImage = `url('${url}')`
    }
    if (this.hasBackgroundRepeatTarget) {
      this.previewTarget.style.backgroundRepeat = this.backgroundRepeatTarget.value
    }
    if (this.hasBackgroundSizeTarget) {
      this.previewTarget.style.backgroundSize = this.backgroundSizeTarget.value
    }
    if (this.hasBackgroundPositionTarget) {
      this.previewTarget.style.backgroundPosition = this.backgroundPositionTarget.value
    }
    if (this.hasBackgroundAttachmentTarget) {
      this.previewTarget.style.backgroundAttachment = this.backgroundAttachmentTarget.value
    }
    this.updateJsonOutput()
  }

}
