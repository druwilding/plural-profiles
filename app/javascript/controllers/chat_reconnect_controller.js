import { Controller } from "@hotwired/stimulus"

// Catches a chat page up after its live connection has dropped.
//
// Action Cable reconnects by itself after a laptop sleeps or the network
// drops, but anything broadcast while it was down is gone: there's no replay.
// Without this, a page left open for a day comes back looking live while
// still showing whatever it had before the gap, and new messages,
// unread dots and channel changes from that time never appear.
//
// Every turbo_stream_from element (<turbo-cable-stream-source>) carries a
// `connected` attribute while its subscription is up. When one loses it and
// later gets it back, this reloads the page, which brings in everything
// missed.
//
// If the connection stays down, it reloads anyway once the tab is in view:
// the server refuses to reconnect a session that has ended, and Action Cable
// then stops trying for good. That reload is a full page load rather than a
// Turbo visit, because a signed-out chat page redirects to the main site to
// sign in, and Turbo's fetch can't follow a redirect to another origin (see
// the sign-out button in layouts/chat.html.haml).
//
// A message being typed survives the reload, but only for the account that
// typed it: after signing in again, someone else could be using the tab. If
// it can't be kept, the page doesn't reload. Other forms with unsaved
// changes (channel or server settings) don't reload at all: a stale unread
// dot is better than losing someone's edits, and the next visit catches up.
//
// Long enough that Action Cable's own reconnect (which retries every 6 to
// 12 seconds or so) usually gets there first
const STILL_DOWN_AFTER = 20_000
const DRAFT_KEY = "chat-reconnect-draft"

export default class extends Controller {
  static values = { user: String }

  connect() {
    this.lostAt = null
    this.refreshing = false
    // A picker sets its hidden fields' values, which also changes the default
    // the browser keeps for them, so they're compared with these instead
    this.loadedValues = new Map(this.#hiddenFields().map(field => [ field, field.value ]))

    this.observer = new MutationObserver(mutations => this.#connectionChanged(mutations))
    this.observer.observe(this.element, {
      subtree: true,
      attributes: true,
      attributeFilter: [ "connected" ],
      attributeOldValue: true
    })

    this.visibilityChanged = this.#visibilityChanged.bind(this)
    document.addEventListener("visibilitychange", this.visibilityChanged)

    requestAnimationFrame(() => this.#restoreDraft())
  }

  disconnect() {
    this.observer.disconnect()
    clearTimeout(this.stillDownTimer)
    document.removeEventListener("visibilitychange", this.visibilityChanged)
  }

  // --- private ---

  #connectionChanged(mutations) {
    mutations.forEach(({ target, oldValue }) => {
      if (target.localName !== "turbo-cable-stream-source") return

      const connected = target.hasAttribute("connected")
      if (!connected && oldValue !== null && !this.lostAt) {
        this.lostAt = Date.now()
        this.stillDownTimer = setTimeout(() => this.#checkStillDown(), STILL_DOWN_AFTER)
      } else if (connected && oldValue === null && this.lostAt) {
        clearTimeout(this.stillDownTimer)
        this.#refresh({ fullLoad: false })
      }
    })
  }

  // A hidden tab waits until it's back in view
  #visibilityChanged() {
    if (document.visibilityState === "visible") this.#checkStillDown()
  }

  #checkStillDown() {
    if (document.visibilityState !== "visible" || !this.lostAt) return
    if (Date.now() - this.lostAt < STILL_DOWN_AFTER) return
    if (this.element.querySelector("turbo-cable-stream-source[connected]")) return
    this.#refresh({ fullLoad: true })
  }

  #refresh({ fullLoad }) {
    if (this.refreshing || this.#hasUnsavedChanges() || !this.#saveDraft()) return
    this.refreshing = true

    if (fullLoad || !window.Turbo) {
      window.location.reload()
    } else {
      Turbo.visit(window.location.href, { action: "replace" })
    }
  }

  #composer() {
    return this.element.querySelector("textarea[data-composer-target='textarea']")
  }

  // In sessionStorage rather than memory, so it survives a full page load,
  // including a detour through signing in again. False if there's a draft
  // that couldn't be kept.
  #saveDraft() {
    const textarea = this.#composer()
    if (!textarea?.value) return true

    try {
      sessionStorage.setItem(DRAFT_KEY, JSON.stringify({
        user: this.userValue,
        url: window.location.href,
        value: textarea.value,
        focused: document.activeElement === textarea,
        selectionStart: textarea.selectionStart,
        selectionEnd: textarea.selectionEnd
      }))
      return true
    } catch {
      // Storage switched off or full
      return false
    }
  }

  #restoreDraft() {
    let draft
    try {
      draft = JSON.parse(sessionStorage.getItem(DRAFT_KEY))
      sessionStorage.removeItem(DRAFT_KEY)
    } catch { return }

    const textarea = this.#composer()
    if (!draft || !textarea || !this.userValue || draft.user !== this.userValue) return
    if (draft.url !== window.location.href || textarea.value) return

    textarea.value = draft.value
    // Resizes the box and previews proxy brackets, as typing would
    textarea.dispatchEvent(new Event("input", { bubbles: true }))
    if (draft.focused) {
      textarea.focus()
      textarea.setSelectionRange(draft.selectionStart, draft.selectionEnd)
    }
  }

  #forms() {
    const composerForm = this.#composer()?.form
    return Array.from(this.element.querySelectorAll("form")).filter(form => form !== composerForm)
  }

  #hiddenFields() {
    return this.#forms().flatMap(form => Array.from(form.elements).filter(field => field.type === "hidden"))
  }

  // Fields in forms other than the message composer whose value differs
  // from the one the page loaded with
  #hasUnsavedChanges() {
    return this.#forms().some(form => Array.from(form.elements).some(field => {
      if (field.disabled) return false
      if (field.type === "hidden") return this.loadedValues.has(field) && field.value !== this.loadedValues.get(field)
      if (field.type === "checkbox" || field.type === "radio") return field.checked !== field.defaultChecked
      if (field.localName === "select") return Array.from(field.options).some(option => option.selected !== option.defaultSelected)
      if (field.localName === "input" || field.localName === "textarea") return field.value !== field.defaultValue
      return false
    }))
  }
}
