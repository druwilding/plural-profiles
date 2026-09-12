import { Controller } from "@hotwired/stimulus"
import Coloris from "@melloware/coloris"

// Accepts what someone may have typed so far ("ff0000", " #ff0000") and
// returns a usable #RRGGBB(AA), or null if it isn't a colour yet.
function normalizeHex(raw) {
  let value = (raw || "").trim()
  if (value.length && value[0] !== "#") value = `#${value}`
  return /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(value) ? value : null
}

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
    this.initInheritStates()
    this.applyAllToPreview()
    this.applyBackgroundToPreview()
  }

  // Reverse index of the fallback map: profile property -> the chat properties
  // that follow it. Changing a profile colour has to repaint every chat colour
  // currently following it, and scanning all 27 keys on every keystroke would
  // be wasteful.
  buildDependents() {
    this.dependents = {}
    const chain = this.hasFallbackChainValue ? this.fallbackChainValue : {}
    for (const [property, parent] of Object.entries(chain)) {
      (this.dependents[parent] ||= []).push(property)
    }
  }

  // The server renders an inheriting colour's input already disabled, but the
  // presentation that hangs off that state is applied by setInherit — so
  // without this, a freshly-loaded page shows inherited rows undimmed and,
  // more to the point, leaves Coloris's trigger button live on a field that
  // can't be edited. Presentation only: values are left exactly as rendered.
  initInheritStates() {
    this.inheritGroupTargets.forEach(group => {
      this.syncInheritPresentation(group.dataset.property, this.isInheriting(group.dataset.property))
    })
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

  // What a property shows when it isn't set: the value of the profile colour
  // it follows — the same rule Theme#color_for applies server-side. Every
  // fallback points straight at a profile key (enforced by a model test), so
  // this is one lookup, never a walk.
  inheritedValue(property) {
    const chain = this.hasFallbackChainValue ? this.fallbackChainValue : {}
    const parent = chain[property]
    if (!parent) return null
    const input = this.hexInputTargets.find(el => el.dataset.property === parent)
    // Normalized, because the parent's input may hold a half-typed value.
    return input ? normalizeHex(input.value) : null
  }

  // Repaints every chat colour currently following `property`.
  refreshDependents(property) {
    (this.dependents[property] || []).forEach(child => {
      if (!this.isInheriting(child)) return
      const value = this.inheritedValue(child)
      if (!value) return
      this.setInputs(child, value)
      this.applyToPreview(child, value)
    })
  }

  setInputs(property, value) {
    const hexInput = this.hexInputTargets.find(el => el.dataset.property === property)
    const colorInput = this.colorInputTargets.find(el => el.dataset.property === property)
    if (hexInput) hexInput.value = value
    if (colorInput) colorInput.value = value.slice(0, 7)
  }

  // The per-colour "Override" checkbox. Ticked means the colour is set for
  // chat; unticked means it follows its profile counterpart.
  toggleInherit(event) {
    const property = event.currentTarget.dataset.property
    this.setInherit(property, !event.currentTarget.checked)
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

    this.syncInheritPresentation(property, inheriting)

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


  syncInheritPresentation(property, inheriting) {
    const hexInput = this.hexInputTargets.find(el => el.dataset.property === property)
    if (!hexInput) return

    // Coloris replaces the hex input with its own wrapper and trigger button;
    // disabling the input alone still leaves that button clickable, so the
    // picker would open for a field that can't be edited.
    const field = hexInput.closest(".clr-field")
    const trigger = field && field.querySelector("button")
    if (trigger) trigger.disabled = inheriting

    const group = this.groupFor(property)
    if (!group) return
    group.classList.toggle("theme-designer__color-group--inheriting", inheriting)
    const hint = group.querySelector(".theme-designer__inherit-hint")
    if (hint) hint.hidden = !inheriting
    const checkbox = group.querySelector('input[type="checkbox"]')
    if (checkbox) checkbox.checked = !inheriting
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
    const value = normalizeHex(input.value)
    if (!value) return

    this.applyToPreview(property, value)
    this.refreshDependents(property)
    this.updateJsonOutput()
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
