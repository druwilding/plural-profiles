import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Reorder mode for the "our" sidebar. Toggling it on adds a drag handle to
// every item marked with data-reorder-item (see ReorderHelper). Each change
// is saved to Our::OrderingsController straight away.
//
// The handle is also a button, so dragging isn't the only way: with it
// focused, the up and down arrow keys move the item, and the new position is
// announced.
//
// An item's list is its data-reorder-list plus data-reorder-group. Items only
// ever move among the items of their own list: a group's child groups and its
// profiles share one <ul>, but are two lists, so neither can be dragged into
// the other.
//
// The mode survives navigating between pages in the same tab, so someone can
// work through several groups without switching it on again each time.
const STORAGE_KEY = "sidebar-reorder"

export default class extends Controller {
  static targets = ["toggle", "hint", "error", "status"]
  static values = { url: String }

  connect() {
    this.sortables = []
    this.queue = Promise.resolve()
    // Bumped when a list's save fails, so saves already queued for that list
    // (built on the order that failed) are dropped rather than sent
    this.generations = new Map()
    // A Turbo snapshot taken while reordering is still in reorder mode, and
    // still has whatever was last announced or shown as an error
    this.#stop()
    this.statusTarget.textContent = ""
    this.#clearError()
    if (this.#stored()) this.#start()
  }

  disconnect() {
    this.#stop()
  }

  toggle() {
    this.active ? this.#stop() : this.#start()
    this.#store(this.active)
    // The new controls appear silently, and a changed button name isn't
    // always read out on the focused button
    this.#announce(this.active
      ? "Reorder mode on. Each group and profile now has a handle: drag it, or focus it and use the up and down arrow keys."
      : "Reorder mode off.")
  }

  moveWithKeys(event) {
    const direction = { ArrowUp: -1, ArrowDown: 1 }[event.key]
    if (!direction) return
    // Not scroll the sidebar
    event.preventDefault()
    if (this.paused) return
    this.#move(event.currentTarget, direction)
  }

  // The handle sits inside <summary> for groups, where a click (including
  // Enter or Space on the handle) would open or close the group
  ignoreClick(event) {
    event.preventDefault()
  }

  // Sorts a list back to A–Z. The server knows the alphabetical order (names,
  // then labels), so this reloads the page rather than sorting here.
  async reset(event) {
    event.preventDefault()
    const button = event.currentTarget
    if (!confirm(`Sort ${button.dataset.reorderWithin} A–Z? This replaces the order you've chosen.`)) return

    // No more moves until the page reloads, and let those already on their
    // way land first (including any queued while waiting), or one could undo
    // the sort
    this.#pause(true)
    let pending
    do {
      pending = this.queue
      await pending
    } while (pending !== this.queue)

    try {
      await this.#send({ list: button.dataset.reorderReset, reset: "true" })
      window.Turbo ? Turbo.visit(window.location.href, { action: "replace" }) : window.location.reload()
    } catch (status) {
      this.#showError(status)
      this.#pause(false)
    }
  }

  // --- private ---

  #start() {
    this.active = true
    this.element.classList.add("sidebar--reordering")
    this.toggleTarget.setAttribute("aria-pressed", "true")
    this.toggleTarget.title = "Done reordering"
    this.hintTarget.hidden = false
    this.paused = false
    // Per list, the order last saved
    this.saved = new Map()

    this.#items().forEach(item => {
      this.#addControls(item)
      const key = this.#key(item)
      if (!this.saved.has(key)) this.saved.set(key, this.#ids(item.parentElement, key))
    })

    this.#containers().forEach(container => {
      this.sortables.push(Sortable.create(container, {
        handle: ".reorder-handle",
        draggable: "li[data-reorder-item]",
        animation: 150,
        // Pointer events rather than native drag and drop, which browsers
        // handle inconsistently and touch screens not at all
        forceFallback: true,
        // Only within the dragged item's own list
        onMove: ({ dragged, related }) => this.#key(dragged) === this.#key(related),
        onEnd: ({ item, oldIndex, newIndex }) => {
          if (oldIndex !== newIndex) this.#changed(item)
        }
      }))
    })
  }

  #stop() {
    this.active = false
    this.sortables?.forEach(sortable => sortable.destroy())
    this.sortables = []
    this.element.classList.remove("sidebar--reordering")
    if (this.hasToggleTarget) {
      this.toggleTarget.setAttribute("aria-pressed", "false")
      this.toggleTarget.title = "Reorder groups and profiles"
    }
    if (this.hasHintTarget) this.hintTarget.hidden = true
    this.#removeControls()
  }

  #move(handle, direction) {
    const item = handle.closest("li[data-reorder-item]")
    const siblings = this.#siblings(item)
    const neighbour = siblings[siblings.indexOf(item) + direction]
    if (!neighbour) {
      this.#announce(`${item.dataset.reorderName} is already ${direction < 0 ? "first" : "last"} in ${item.dataset.reorderWithin}.`)
      return
    }

    direction < 0 ? neighbour.before(item) : neighbour.after(item)
    // Moving the item takes focus out of it; put it back
    handle.focus()
    this.#changed(item)
  }

  #changed(item) {
    const key = this.#key(item)
    const ids = this.#ids(item.parentElement, key)
    const position = ids.indexOf(item.dataset.reorderId) + 1

    this.#syncCopies(key, ids, item.parentElement)
    this.#announce(`${item.dataset.reorderName} moved to position ${position} of ${ids.length} in ${item.dataset.reorderWithin}.`)
    this.#save(key, item, ids)
  }

  // Saves one at a time, in order, so a quick run of moves can't land out of
  // order on the server.
  #save(key, item, ids) {
    const params = { list: item.dataset.reorderList, group: item.dataset.reorderGroup, ids }
    const generation = this.generations.get(key) || 0

    this.queue = this.queue.then(async () => {
      // An earlier save for this list failed and it's been put back since
      if ((this.generations.get(key) || 0) !== generation) return

      try {
        // As of the save before this one, so read here rather than when queued
        await this.#send({ ...params, previous: this.#storedPositions(key) })
        this.saved.set(key, ids)
        this.#setStoredPositions(key, ids)
        if (this.errorKey === key) this.#clearError()
      } catch (status) {
        this.generations.set(key, generation + 1)
        // Put the list back the way it was last saved
        this.#syncCopies(key, this.saved.get(key) || [])
        this.#showError(status, key)
      }
    })
  }

  async #send(params) {
    const response = await fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: JSON.stringify(params),
      credentials: "same-origin"
    })
    // A signed-out session is redirected to the sign-in page, which fetch
    // follows and reports as a success
    if (response.redirected) throw "signed-out"
    if (!response.ok) throw response.status
  }

  // Each item's data-reorder-position is its position as the server last had
  // it, sent with each save so the server can tell whether another tab has
  // reordered the list since (see ListOrder). Kept on the items rather than
  // in the controller, so it survives switching reorder mode off and on, and
  // Turbo's cached copy of the page.
  #storedPositions(key) {
    return Object.fromEntries(this.#items()
      .filter(item => this.#key(item) === key)
      .map(item => [ item.dataset.reorderId, item.dataset.reorderPosition === "" ? null : Number(item.dataset.reorderPosition) ]))
  }

  // Every copy of the list, for a group shown in more than one place
  #setStoredPositions(key, ids) {
    this.#items()
      .filter(item => this.#key(item) === key)
      .forEach(item => { item.dataset.reorderPosition = ids.indexOf(item.dataset.reorderId) })
  }

  // While a Sort A–Z is on its way, so no move can land after it
  #pause(paused) {
    this.paused = paused
    this.sortables.forEach(sortable => sortable.option("disabled", paused))
  }

  // A group that sits inside several parents appears in the sidebar once
  // for each, so its contents do too. Every copy of a list follows the
  // newest order.
  #syncCopies(key, ids, except = null) {
    const focused = document.activeElement

    this.#containers().forEach(container => {
      if (container === except) return
      const items = Array.from(container.children).filter(child => child.matches("li[data-reorder-item]") && this.#key(child) === key)
      if (items.length === 0) return

      const byId = new Map(items.map(child => [ child.dataset.reorderId, child ]))
      // Keep the list's place among the other list sharing this container,
      // and only move items that are out of place
      const marker = document.createComment("reorder")
      items[0].before(marker)
      let previous = marker
      ids.forEach(id => {
        const child = byId.get(id)
        if (!child) return
        if (previous.nextSibling !== child) previous.after(child)
        previous = child
      })
      marker.remove()
    })

    // Moving an item takes focus out of it; give it back
    if (focused?.isConnected && document.activeElement !== focused) focused.focus()
  }

  #addControls(item) {
    const row = item.querySelector(":scope > details > summary") || item
    const handle = document.createElement("button")
    handle.type = "button"
    handle.className = "reorder-handle"
    handle.title = "Drag to reorder"
    // The key instructions, read after the name (see _sidebar.html.haml)
    handle.setAttribute("aria-describedby", "sidebar-reorder-keys")
    handle.dataset.action = "keydown->sidebar-reorder#moveWithKeys click->sidebar-reorder#ignoreClick"
    handle.innerHTML = `${GRIP_ICON}<span class="visually-hidden"></span>`
    handle.querySelector(".visually-hidden").textContent = `Reorder ${item.dataset.reorderName}`
    row.prepend(handle)
  }

  #removeControls() {
    this.element.querySelectorAll(".reorder-handle").forEach(el => el.remove())
  }

  #items() {
    return Array.from(this.element.querySelectorAll("li[data-reorder-item]"))
  }

  #containers() {
    return Array.from(new Set(this.#items().map(item => item.parentElement)))
  }

  #siblings(item) {
    const key = this.#key(item)
    return Array.from(item.parentElement.children).filter(child => child.matches("li[data-reorder-item]") && this.#key(child) === key)
  }

  #ids(container, key) {
    return Array.from(container.children)
      .filter(child => child.matches("li[data-reorder-item]") && this.#key(child) === key)
      .map(child => child.dataset.reorderId)
  }

  #key(item) {
    return `${item.dataset.reorderList}:${item.dataset.reorderGroup || ""}`
  }

  #announce(message) {
    if (!this.hasStatusTarget) return
    // Clearing first makes a repeated message (two moves in a row to the
    // same position) be read out again
    this.statusTarget.textContent = ""
    requestAnimationFrame(() => { this.statusTarget.textContent = message })
  }

  #showError(status, key = null) {
    this.errorKey = key
    const message = {
      409: "This list has changed since the page loaded. Reload the page to reorder it.",
      "signed-out": "You've been signed out. Sign in again to save the new order."
    }[status] || "Couldn't save the new order. Please try again."
    // Cleared first, so the same message twice in a row is still read out
    this.errorTarget.textContent = ""
    requestAnimationFrame(() => { this.errorTarget.textContent = message })
  }

  #clearError() {
    this.errorKey = null
    this.errorTarget.textContent = ""
  }

  #stored() {
    try { return sessionStorage.getItem(STORAGE_KEY) === "on" } catch { return false }
  }

  #store(on) {
    try { on ? sessionStorage.setItem(STORAGE_KEY, "on") : sessionStorage.removeItem(STORAGE_KEY) } catch { /* private mode */ }
  }
}

const GRIP_ICON = `<svg width="12" height="16" viewBox="0 0 12 16" fill="currentColor" aria-hidden="true" focusable="false"><circle cx="3" cy="3" r="1.5"/><circle cx="9" cy="3" r="1.5"/><circle cx="3" cy="8" r="1.5"/><circle cx="9" cy="8" r="1.5"/><circle cx="3" cy="13" r="1.5"/><circle cx="9" cy="13" r="1.5"/></svg>`
