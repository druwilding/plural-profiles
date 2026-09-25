import { Controller } from "@hotwired/stimulus"

// The page for uploaded files that need a decision. As a new name is typed,
// picks "Add it as a new emote" and says what code it will get, or that the
// name is taken too (by an existing emote, from takenValue, or by another
// file on this page). The server checks everything again on save.
export default class extends Controller {
  static targets = [ "row" ]
  static values = { taken: Object }

  connect() {
    this.update()
  }

  nameChanged(event) {
    const create = event.target.closest("[data-emote-upload-decision-target='row']").querySelector("[data-field='create']")
    create.checked = true
    this.update()
  }

  update() {
    const seen = new Map()
    this.rowTargets.forEach((row, index) => {
      const name = row.querySelector("[data-field='name']").value.trim().toLowerCase().replace(/_/g, "-")
      const code = defaultCode(name)
      const identifiers = [ ...new Set([ name, code ].filter(Boolean)) ]
      const creating = row.querySelector("[data-field='create']").checked
      const status = row.querySelector("[data-field='status']")

      const taken = identifiers.map((identifier) => this.takenValue[identifier]).find(Boolean)
      const other = identifiers.map((identifier) => seen.get(identifier)).find((value) => value !== undefined)

      if (!name) {
        status.textContent = "Needs a name."
      } else if (taken) {
        status.textContent = `“${name}” is already used by ${taken.name}.`
      } else if (other !== undefined) {
        status.textContent = `Another file on this page is also called “${name}”.`
      } else {
        status.textContent = `It will be typed as :${code}:`
      }
      if (creating) identifiers.forEach((identifier) => seen.set(identifier, index))
    })
  }
}

// Mirrors Emote.default_code: drop the number prefix that sets the order,
// unless the number is the emote itself (100, 1st-place).
function defaultCode(name) {
  if (/^\d+$/.test(name)) return name
  if (/^\d+(st|nd|rd|th)(-|$)/.test(name)) return name
  return name.replace(/^\d+-?/, "") || name
}
