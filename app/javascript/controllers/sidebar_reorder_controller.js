import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Reorder mode for the "our" sidebar. Toggling it on adds a drag handle and
// "Move up" / "Move down" buttons to every item marked with
// data-reorder-item (see ReorderHelper). Each change is saved to
// Our::OrderingsController straight away.
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
      ? "Reorder mode on. Each group and profile now has Move up and Move down buttons."
      : "Reorder mode off.")
  }

  moveUp(event) {
    this.#move(event, -1)
  }

  moveDown(event) {
    this.#move(event, 1)
  }

  // Sorts a list back to A–Z. The server knows the alphabetical order (names,
  // then labels), so this reloads the page rather than sorting here.
  async reset(event) {
    event.preventDefault()
    const button = event.currentTarget
    const within = button.dataset.reorderWithin
    if (!confirm(`Sort ${within} A–Z? This replaces the order you've chosen.`)) return

    const lists = button.dataset.reorderReset === "group"
      ? [ { list: "group_groups", group: button.dataset.reorderGroup }, { list: "group_profiles", group: button.dataset.reorderGroup } ]
      : [ { list: button.dataset.reorderReset } ]

    // Let moves already on their way land first, or one could undo the sort
    await this.queue

    let sorted = 0
    try {
      for (const params of lists) {
        await this.#send({ ...params, reset: "true" })
        sorted++
      }
    } catch (status) {
      this.#showError(status)
      // Nothing changed, so the page is still right
      if (sorted === 0) return
    }
    // Reload even after a partly failed group sort, so the page shows what
    // the server now has
    window.Turbo ? Turbo.visit(window.location.href, { action: "replace" }) : window.location.reload()
  }

  // --- private ---

  #start() {
    this.active = true
    this.element.classList.add("sidebar--reordering")
    this.toggleTarget.textContent = "Done reordering"
    this.hintTarget.hidden = false
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

    this.#updateButtons()
  }

  #stop() {
    this.active = false
    this.sortables?.forEach(sortable => sortable.destroy())
    this.sortables = []
    this.element.classList.remove("sidebar--reordering")
    if (this.hasToggleTarget) this.toggleTarget.textContent = "Reorder"
    if (this.hasHintTarget) this.hintTarget.hidden = true
    this.#removeControls()
  }

  #move(event, direction) {
    // The buttons sit inside <summary> for groups; don't open or close it
    event.preventDefault()
    const button = event.currentTarget
    if (button.getAttribute("aria-disabled") === "true") return

    const item = button.closest("li[data-reorder-item]")
    const siblings = this.#siblings(item)
    const index = siblings.indexOf(item)
    const neighbour = siblings[index + direction]
    if (!neighbour) return

    direction < 0 ? neighbour.before(item) : neighbour.after(item)
    this.#changed(item)

    // Moving the item takes focus with it; put it back on the same button,
    // or on the other one if this item has just reached the end of its list.
    const other = item.querySelector(direction < 0 ? ".reorder-btn--down" : ".reorder-btn--up")
    const focusable = button.getAttribute("aria-disabled") === "true" ? other : button
    focusable.focus()
  }

  #changed(item) {
    const key = this.#key(item)
    const ids = this.#ids(item.parentElement, key)
    const position = ids.indexOf(item.dataset.reorderId) + 1

    this.#syncCopies(key, ids, item.parentElement)
    this.#updateButtons()
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
        await this.#send(params)
        this.saved.set(key, ids)
        if (this.errorKey === key) this.#clearError()
      } catch (status) {
        this.generations.set(key, generation + 1)
        // Put the list back the way it was last saved
        this.#syncCopies(key, this.saved.get(key) || [])
        this.#updateButtons()
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
    if (!response.ok) throw response.status
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
    const name = item.dataset.reorderName
    const row = item.querySelector(":scope > details > summary") || item
    const controls = document.createElement("span")
    controls.className = "reorder-controls"

    const handle = document.createElement("span")
    handle.className = "reorder-handle"
    handle.setAttribute("aria-hidden", "true")
    handle.title = "Drag to reorder"
    handle.innerHTML = GRIP_ICON
    row.prepend(handle)

    // Inside a group's <summary>, a click anywhere opens or closes the group
    for (const el of [ handle, controls ]) {
      el.addEventListener("click", event => {
        if (event.target.closest("a") === null) event.preventDefault()
      })
    }

    if (item.querySelector(":scope > details") && item.dataset.reorderList !== "profiles") {
      const group = item.dataset.reorderId
      const reset = this.#button("reorder-btn reorder-btn--reset", `Sort ${name}'s contents A–Z`, `<span aria-hidden="true">A–Z</span>`)
      reset.dataset.action = "sidebar-reorder#reset"
      reset.dataset.reorderReset = "group"
      reset.dataset.reorderGroup = group
      reset.dataset.reorderWithin = `${name}'s contents`
      controls.append(reset)
    }

    const up = this.#button("reorder-btn reorder-btn--up", `Move ${name} up`, ARROW_UP)
    up.dataset.action = "sidebar-reorder#moveUp"
    const down = this.#button("reorder-btn reorder-btn--down", `Move ${name} down`, ARROW_DOWN)
    down.dataset.action = "sidebar-reorder#moveDown"
    controls.append(up, down)
    row.append(controls)
  }

  #button(className, label, content) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = `btn--secondary ${className}`
    button.title = label
    button.innerHTML = `${content}<span class="visually-hidden"></span>`
    button.querySelector(".visually-hidden").textContent = label
    return button
  }

  #removeControls() {
    this.element.querySelectorAll(".reorder-controls, .reorder-handle").forEach(el => el.remove())
  }

  // First and last items can't move further. aria-disabled rather than
  // disabled, so a button keeps focus when its item reaches the end.
  #updateButtons() {
    this.#items().forEach(item => {
      const siblings = this.#siblings(item)
      const index = siblings.indexOf(item)
      item.querySelector(".reorder-btn--up")?.setAttribute("aria-disabled", index === 0)
      item.querySelector(".reorder-btn--down")?.setAttribute("aria-disabled", index === siblings.length - 1)
    })
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
    const message = status === 409
      ? "This list has changed since the page loaded. Reload the page to reorder it."
      : "Couldn't save the new order. Please try again."
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

const GRIP_ICON = `<svg width="12" height="16" viewBox="0 0 12 16" fill="currentColor" focusable="false"><circle cx="3" cy="3" r="1.5"/><circle cx="9" cy="3" r="1.5"/><circle cx="3" cy="8" r="1.5"/><circle cx="9" cy="8" r="1.5"/><circle cx="3" cy="13" r="1.5"/><circle cx="9" cy="13" r="1.5"/></svg>`
const ARROW_UP = `<svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true" focusable="false"><path d="M2 8l4-4 4 4"/></svg>`
const ARROW_DOWN = `<svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true" focusable="false"><path d="M2 4l4 4 4-4"/></svg>`
