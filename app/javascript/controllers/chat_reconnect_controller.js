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
// missed. It also reloads when the tab comes back into view with the
// connection still down for a while: the server refuses to reconnect a
// session that has ended, and Action Cable then stops trying for good.
//
// A message being typed survives the reload. Other forms with unsaved
// changes (channel or server settings) don't reload at all: a stale unread
// dot is better than losing someone's edits, and the next visit catches up.
const STILL_DOWN_AFTER = 10_000

// Kept between the page that reloads and the one that replaces it
let pendingDraft = null

export default class extends Controller {
  connect() {
    this.lostAt = null
    this.refreshing = false

    this.observer = new MutationObserver(mutations => this.#connectionChanged(mutations))
    this.observer.observe(this.element, {
      subtree: true,
      attributes: true,
      attributeFilter: [ "connected" ],
      attributeOldValue: true
    })

    this.visibilityChanged = this.#visibilityChanged.bind(this)
    document.addEventListener("visibilitychange", this.visibilityChanged)

    if (pendingDraft) requestAnimationFrame(() => this.#restoreDraft())
  }

  disconnect() {
    this.observer.disconnect()
    document.removeEventListener("visibilitychange", this.visibilityChanged)
  }

  // --- private ---

  #connectionChanged(mutations) {
    mutations.forEach(({ target, oldValue }) => {
      if (target.localName !== "turbo-cable-stream-source") return

      const connected = target.hasAttribute("connected")
      if (!connected && oldValue !== null) {
        this.lostAt ??= Date.now()
      } else if (connected && oldValue === null && this.lostAt) {
        this.#refresh()
      }
    })
  }

  #visibilityChanged() {
    if (document.visibilityState !== "visible" || !this.lostAt) return
    if (Date.now() - this.lostAt > STILL_DOWN_AFTER) this.#refresh()
  }

  #refresh() {
    if (this.refreshing || this.#hasUnsavedChanges()) return
    this.refreshing = true

    pendingDraft = this.#draft()
    window.Turbo ? Turbo.visit(window.location.href, { action: "replace" }) : window.location.reload()
  }

  #composer() {
    return this.element.querySelector("textarea[data-composer-target='textarea']")
  }

  #draft() {
    const textarea = this.#composer()
    if (!textarea?.value) return null

    return {
      url: window.location.href,
      value: textarea.value,
      focused: document.activeElement === textarea,
      selectionStart: textarea.selectionStart,
      selectionEnd: textarea.selectionEnd
    }
  }

  #restoreDraft() {
    const draft = pendingDraft
    pendingDraft = null
    const textarea = this.#composer()
    if (!textarea || draft.url !== window.location.href || textarea.value) return

    textarea.value = draft.value
    // Resizes the box and previews proxy brackets, as typing would
    textarea.dispatchEvent(new Event("input", { bubbles: true }))
    if (draft.focused) {
      textarea.focus()
      textarea.setSelectionRange(draft.selectionStart, draft.selectionEnd)
    }
  }

  // Fields in forms other than the message composer whose value differs
  // from the one the page loaded with
  #hasUnsavedChanges() {
    const composerForm = this.#composer()?.form
    return Array.from(this.element.querySelectorAll("form")).some(form =>
      form !== composerForm && Array.from(form.elements).some(field => {
        if (field.disabled || field.type === "hidden") return false
        if (field.type === "checkbox" || field.type === "radio") return field.checked !== field.defaultChecked
        if (field.localName === "select") return Array.from(field.options).some(option => option.selected !== option.defaultSelected)
        if (field.localName === "input" || field.localName === "textarea") return field.value !== field.defaultValue
        return false
      }))
  }
}
