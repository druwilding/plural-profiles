import { Controller } from "@hotwired/stimulus"
import Coloris from "@melloware/coloris"

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
  static targets = ["colorInput", "hexInput", "preview", "jsonOutput", "inheritGroup",
                    "nameInput", "creditInput", "creditUrlInput", "notesInput", "tagInput",
                    "backgroundFileInput", "backgroundRepeat",
                    "backgroundSize", "backgroundPosition", "backgroundAttachment",
                    "previewPanel", "previewTab"]

  // Both populated from the model via data attributes so the Ruby and JS
  // definitions stay in sync: derivedTextProperties from
  // Theme::DERIVED_TEXT_PROPERTIES, fallbackChain from Theme::FALLBACK_CHAIN.
  static values = { derivedTextProperties: Object, fallbackChain: Object, exportVersion: Number }

  connect() {
    this.bgObjectUrl = null
    this.buildDependents()
    this.initColoris()
    this.applyAllToPreview()
    this.applyBackgroundToPreview()
  }

  // Reverse index of the fallback chain: property -> the properties that
  // inherit from it. Changing a profile colour has to repaint every chat
  // colour currently following it (and anything following those in turn), and
  // walking the forward chain for all 28 keys on every keystroke would be
  // wasteful.
  buildDependents() {
    this.dependents = {}
    const chain = this.hasFallbackChainValue ? this.fallbackChainValue : {}
    for (const [property, parent] of Object.entries(chain)) {
      (this.dependents[parent] ||= []).push(property)
    }
  }

  // The group element wrapping one colour row, or null for a property that
  // can't inherit.
  groupFor(property) {
    return this.inheritGroupTargets.find(el => el.dataset.property === property)
  }

  isInheriting(property) {
    const hexInput = this.hexInputTargets.find(el => el.dataset.property === property)
    return hexInput ? hexInput.disabled : false
  }

  // Resolves what a property shows when it isn't set, by walking up to the
  // first ancestor that is — the same rule Theme#color_for applies server-side.
  inheritedValue(property) {
    const chain = this.hasFallbackChainValue ? this.fallbackChainValue : {}
    const seen = new Set()
    let current = chain[property]
    while (current && !seen.has(current)) {
      seen.add(current)
      if (!this.isInheriting(current)) {
        const input = this.hexInputTargets.find(el => el.dataset.property === current)
        if (input) return input.value
      }
      current = chain[current]
    }
    return null
  }

  // Repaints every property inheriting from `property`, recursively, so a
  // two-hop chain (chat_topbar_bg -> chat_pane_bg -> pane_bg) updates all the
  // way down from a single edit.
  refreshDependents(property) {
    (this.dependents[property] || []).forEach(child => {
      if (!this.isInheriting(child)) return
      const value = this.inheritedValue(child)
      if (!value) return
      this.setInputs(child, value)
      this.applyToPreview(child, value)
      this.refreshDependents(child)
    })
  }

  setInputs(property, value) {
    const hexInput = this.hexInputTargets.find(el => el.dataset.property === property)
    const colorInput = this.colorInputTargets.find(el => el.dataset.property === property)
    if (hexInput) hexInput.value = value
    if (colorInput) colorInput.value = value.slice(0, 7)
  }

  // "Use profile colour" / "Set for chat" on one colour.
  toggleInherit(event) {
    const property = event.currentTarget.dataset.property
    this.setInherit(property, event.currentTarget.value === "1")
    this.updateJsonOutput()
  }

  setInherit(property, inheriting) {
    const hexInput = this.hexInputTargets.find(el => el.dataset.property === property)
    if (!hexInput) return

    // Only the hex input's disabled state is touched. initColoris disables
    // every native colour input permanently (Coloris replaces them), so
    // re-enabling one here would resurrect a hidden field that then posts
    // alongside the hex input under the same name.
    hexInput.disabled = inheriting

    // Coloris replaces the hex input with its own wrapper and trigger button;
    // disabling the input alone still leaves that button clickable, so the
    // picker would open for a field that can't be edited.
    const field = hexInput.closest(".clr-field")
    const trigger = field && field.querySelector("button")
    if (trigger) trigger.disabled = inheriting

    const group = this.groupFor(property)
    if (group) {
      group.classList.toggle("theme-designer__color-group--inheriting", inheriting)
      const hint = group.querySelector(".theme-designer__inherit-hint")
      if (hint) hint.hidden = !inheriting
      const radio = group.querySelector(`input[type="radio"][value="${inheriting ? "1" : "0"}"]`)
      if (radio) radio.checked = true
    }

    // Switching back to inheriting snaps the swatch to whatever it's now
    // following; switching to overriding keeps the colour it was showing, so
    // the designer starts from what they can already see rather than a jump.
    if (inheriting) {
      const value = this.inheritedValue(property)
      if (value) {
        this.setInputs(property, value)
        this.applyToPreview(property, value)
      }
    }
    this.refreshDependents(property)
  }

  overrideAllChat() {
    this.chatProperties().forEach(property => this.setInherit(property, false))
    this.updateJsonOutput()
  }

  inheritAllChat() {
    this.chatProperties().forEach(property => this.setInherit(property, true))
    this.updateJsonOutput()
  }

  chatProperties() {
    return this.inheritGroupTargets.map(el => el.dataset.property)
  }

  // Preview tabs: the profile mock and the chat mock share one themed
  // container, so switching is just which panel is visible.
  showPreview(event) {
    const name = event.currentTarget.dataset.previewPanel
    this.previewPanelTargets.forEach(panel => {
      panel.hidden = panel.dataset.previewPanel !== name
    })
    this.previewTabTargets.forEach(tab => {
      const selected = tab.dataset.previewPanel === name
      tab.classList.toggle("theme-designer__preview-tab--active", selected)
      tab.setAttribute("aria-selected", selected ? "true" : "false")
    })
  }

  disconnect() {
    if (this.bgObjectUrl) URL.revokeObjectURL(this.bgObjectUrl)
    this.destroyColoris()
  }

  initColoris() {
    Coloris.init()
    Coloris({
      el: "[data-coloris]",
      alpha: true,
      format: "hex",
      theme: "large",
      themeMode: "auto",
      forceAlpha: false,
    })
    Coloris.wrap("[data-coloris]")
    this.colorInputTargets.forEach(input => {
      input.disabled = true
      input.hidden = true
    })
  }

  destroyColoris() {
    this.colorInputTargets.forEach(input => {
      input.disabled = false
      input.hidden = false
    })
    this.hexInputTargets.forEach(input => {
      const wrapper = input.closest(".clr-field")
      if (wrapper && wrapper.parentNode) {
        wrapper.parentNode.insertBefore(input, wrapper)
        wrapper.remove()
      }
    })
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
    this.refreshDependents(property)
    this.updateJsonOutput()
  }

  // Called when the hex text input changes (also fired by Coloris on pick)
  updateFromHex(event) {
    const input = event.currentTarget
    const property = input.dataset.property
    let value = input.value.trim()

    // Auto-add # prefix
    if (value.length && value[0] !== "#") value = `#${value}`

    // Only apply if it looks like a valid hex colour (6 or 8 digits for alpha)
    if (/^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(value)) {
      this.applyToPreview(property, value)
      this.refreshDependents(property)
      this.updateJsonOutput()
    }
  }

  // Apply a single property to the preview container
  applyToPreview(property, value) {
    if (!this.hasPreviewTarget) return
    this.previewTarget.style.setProperty(cssProp(property), value)

    // Also update computed properties derived from this one. Sources and
    // percentages come from the server via derivedTextPropertiesValue so they
    // stay in sync with Theme::DERIVED_TEXT_PROPERTIES without duplication.
    const derived = this.hasDerivedTextPropertiesValue ? this.derivedTextPropertiesValue : {}
    Object.entries(derived).forEach(([prop, meta]) => {
      if (meta.source !== property) return
      this.previewTarget.style.setProperty(`--${prop}`, `color-mix(in srgb, ${value} ${meta.percent}%, transparent)`)
    })
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

    const data = { plural_profiles_theme: this.hasExportVersionValue ? this.exportVersionValue : 2 }

    if (this.hasNameInputTarget && this.nameInputTarget.value.trim()) {
      data.name = this.nameInputTarget.value.trim()
    }

    // Disabled inputs are the ones set to inherit; they aren't submitted, so
    // they mustn't appear in the export either — an exported inherited colour
    // would import as an explicit override and stop following the profile.
    const colors = {}
    this.hexInputTargets.forEach(input => {
      if (input.disabled) return
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
