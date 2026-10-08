import { Controller } from "@hotwired/stimulus"
import { loadDraft, saveDraft, clearDraft } from "journal_drafts"

// Keeps the Write form as a draft in this browser while someone writes
// (docs/plan-journal.md, "Drafts, saved in the browser"):
//
//  - Saves the whole form a couple of seconds after typing stops, straight
//    away on Ctrl+S (or Cmd+S), and on leaving the page.
//  - "Autosaved draft at 20:22" shows under the text box. Screen readers only
//    hear it after Ctrl+S, not every time it autosaves.
//  - Coming back with a draft offers to restore or discard it, rather than
//    restoring it over the page unasked. Until one is chosen, nothing is
//    saved, so the draft can't be overwritten by accident.
//  - Posting clears it (journal_draft_clear_controller, on the next page).
//
// The date fields start at "now", so a draft's date is only restored if it
// had been changed; otherwise the restored entry is dated when it's posted.

const SAVE_DELAY = 2000
const WRITING_FIELDS = [ "entry[subject]", "entry[body]", "entry[tags]" ]
const DATE_FIELD = /\[datetime_parts\]/

// Seconds for the autosave line, so it's clear it keeps updating; not for
// the restore offer, where they'd only be clutter.
function formatTime(date, { seconds = false } = {}) {
  const time = date.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", ...(seconds && { second: "2-digit" }) })
  if (date.toDateString() === new Date().toDateString()) return time
  return `${date.toLocaleDateString("en-GB", { day: "numeric", month: "long" })}, ${time}`
}

export default class extends Controller {
  static targets = [ "offer", "offerTime", "status", "announce" ]
  static values = { key: String }

  connect() {
    this.initialDate = JSON.stringify(this.dateValues())
    // Choices from the draft this journal doesn't offer (an icon keyword
    // only another journal has), kept in the draft as they were until
    // something else is chosen, so going back to that journal still has them.
    this.carried = {}
    this.submitting = false

    // Offered only on a fresh form: one that came back from a failed post
    // already has the writing in it.
    const draft = loadDraft(this.keyValue)
    if (draft && !this.hasWriting()) {
      this.pendingDraft = draft
      this.offerTimeTarget.textContent = formatTime(new Date(draft.savedAt))
      this.offerTarget.hidden = false
    }

    this.onChange = this.onChange.bind(this)
    this.onKeydown = this.onKeydown.bind(this)
    this.onSubmit = this.onSubmit.bind(this)
    this.onSubmitEnd = this.onSubmitEnd.bind(this)
    this.saveNow = this.saveNow.bind(this)

    this.element.addEventListener("input", this.onChange)
    this.element.addEventListener("change", this.onChange)
    this.element.addEventListener("submit", this.onSubmit)
    this.element.addEventListener("turbo:submit-end", this.onSubmitEnd)
    document.addEventListener("keydown", this.onKeydown)
    document.addEventListener("turbo:before-visit", this.saveNow)
    window.addEventListener("pagehide", this.saveNow)
  }

  disconnect() {
    clearTimeout(this.timer)
    this.element.removeEventListener("input", this.onChange)
    this.element.removeEventListener("change", this.onChange)
    this.element.removeEventListener("submit", this.onSubmit)
    this.element.removeEventListener("turbo:submit-end", this.onSubmitEnd)
    document.removeEventListener("keydown", this.onKeydown)
    document.removeEventListener("turbo:before-visit", this.saveNow)
    window.removeEventListener("pagehide", this.saveNow)
  }

  // -- Restore or discard --

  restore() {
    const draft = this.pendingDraft
    this.closeOffer()
    this.restoring = true
    for (const [ name, value ] of Object.entries(draft.fields || {})) {
      if (DATE_FIELD.test(name) && !draft.dateChanged) continue
      const field = this.element.elements.namedItem(name)
      if (!field) continue
      // An icon this journal doesn't have (another journal's, or since
      // deleted) stays at (default) here, but stays in the draft.
      if (field.tagName === "SELECT" && ![ ...field.options ].some(option => option.value === value)) {
        this.carried[name] = value
        continue
      }
      field.value = value
      if (field.tagName === "SELECT") field.dispatchEvent(new Event("change", { bubbles: true }))
    }
    this.restoring = false
    this.save()
    this.element.elements.namedItem("entry[body]")?.focus()
  }

  discard() {
    clearDraft(this.keyValue)
    this.closeOffer()
    this.element.elements.namedItem("entry[subject]")?.focus()
  }

  closeOffer() {
    this.pendingDraft = null
    this.offerTarget.hidden = true
    this.statusTarget.textContent = ""
  }

  // -- Saving --

  onChange(event) {
    // Someone choosing for themselves (not restore setting it) replaces
    // whatever was carried along for that field.
    if (!this.restoring) delete this.carried[event.target.name]
    if (this.pendingDraft) {
      this.statusTarget.textContent = "Restore or discard the draft above to start saving drafts again."
      return
    }
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.save(), SAVE_DELAY)
  }

  onKeydown(event) {
    if (event.key.toLowerCase() !== "s" || !(event.ctrlKey || event.metaKey) || event.altKey || event.shiftKey) return
    event.preventDefault()
    if (this.pendingDraft) {
      this.announce("Restore or discard the draft above first.")
      return
    }
    clearTimeout(this.timer)
    this.save()
    this.announce(this.statusTarget.textContent)
  }

  // Saved straight away on posting, in case posting fails; after that, not
  // at all, so leaving for the entry page can't save it again after it's
  // been cleared.
  onSubmit() {
    this.saveNow()
    this.submitting = true
  }

  // A post that didn't get a page back (no connection) stays on this page,
  // which keeps drafting.
  onSubmitEnd(event) {
    if (!event.detail.success) this.submitting = false
  }

  saveNow() {
    clearTimeout(this.timer)
    if (!this.submitting) this.save()
  }

  save() {
    if (this.pendingDraft) return

    if (!this.hasWriting()) {
      clearDraft(this.keyValue)
      this.statusTarget.textContent = ""
      return
    }

    const now = new Date()
    const saved = saveDraft(this.keyValue, {
      savedAt: now.toISOString(),
      dateChanged: JSON.stringify(this.dateValues()) !== this.initialDate,
      fields: this.fieldValues()
    })
    this.statusTarget.textContent = saved
      ? `Autosaved draft at ${formatTime(now, { seconds: true })}`
      : "This browser isn't letting us save a draft."
  }

  // -- The form --

  // Everything someone can change, by name: not the hidden fields or the
  // buttons.
  fieldValues() {
    const values = {}
    for (const field of this.element.elements) {
      if (!field.name || [ "hidden", "submit", "button" ].includes(field.type)) continue
      values[field.name] = field.value
    }
    return { ...values, ...this.carried }
  }

  dateValues() {
    return Object.entries(this.fieldValues()).filter(([ name ]) => DATE_FIELD.test(name))
  }

  hasWriting() {
    return WRITING_FIELDS.some(name => this.element.elements.namedItem(name)?.value.trim())
  }

  // Emptied first, so saying the same thing twice is still announced.
  announce(message) {
    this.announceTarget.textContent = ""
    setTimeout(() => { this.announceTarget.textContent = message }, 50)
  }
}
