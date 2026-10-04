import { Controller } from "@hotwired/stimulus"

// Unread dots that arrive live, and the tab that shows them.
//
// When someone posts, the server marks the channel unread for everyone in
// the server (Chat::Message#broadcast_unread_dots), including anyone already
// reading it, whose page then marks it read and clears the dot again
// (channel_read_controller.js). Shown straight away, that dot blinks on and
// off. So a dot that newly arrives live waits a moment before it shows, and
// one that's gone again by then never shows at all. A dot that was already
// showing and is replaced by another stays visible throughout. Dots drawn
// with the page show at once.
//
// While any server in the rail has an unread dot showing, the tab says so:
// the favicon gets a dot, and the title starts with one. The rail has every
// server the person is in, so its dots cover everything unread.
const DELAY = 1500
const CONTAINERS = "[id$='_rail_dot'], [id$='_sidebar_dot']"
const TITLE_DOT = "• "

let badgedIcon = null

export default class extends Controller {
  connect() {
    this.timers = new Map()
    // Always the page's own title: Turbo's cached copy never has the dot (see
    // beforeCache), so nothing here has to guess whether a leading "• " is
    // ours or part of a server's name.
    this.baseTitle = document.title
    // Any left waiting in a cached copy have no timer to show them now
    this.element.querySelectorAll(".unread-dot--pending").forEach(dot => dot.classList.remove("unread-dot--pending"))

    this.observer = new MutationObserver(mutations => this.#changed(mutations))
    this.observer.observe(this.element, { childList: true, subtree: true })
    this.beforeCache = this.#beforeCache.bind(this)
    document.addEventListener("turbo:before-cache", this.beforeCache)
    this.#updateTab()
  }

  disconnect() {
    this.observer.disconnect()
    this.timers.forEach(timer => clearTimeout(timer))
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  // Turbo keeps a copy of the page to show on going back to it. That copy
  // gets the page's own title and favicon, and every unread dot as it stands,
  // so a page restored from it starts clean and this works it all out again.
  #beforeCache() {
    document.title = this.baseTitle
    this.#setFavicon(false)
    this.element.querySelectorAll(".unread-dot--pending").forEach(dot => dot.classList.remove("unread-dot--pending"))
  }

  #changed(mutations) {
    // Whether each dot was showing before this change, by its container
    const showing = new Map()
    mutations.forEach(mutation => mutation.removedNodes.forEach(node => {
      this.#containersIn(node).forEach(container => {
        showing.set(container.id, Boolean(container.querySelector(".unread-dot:not(.unread-dot--pending)")))
      })
    }))

    mutations.forEach(mutation => mutation.addedNodes.forEach(node => {
      this.#containersIn(node).forEach(container => {
        const dot = container.querySelector(".unread-dot")
        if (!dot || showing.get(container.id)) {
          this.#cancel(container.id)
          return
        }
        if (this.timers.has(container.id)) return dot.classList.add("unread-dot--pending")
        dot.classList.add("unread-dot--pending")
        this.timers.set(container.id, setTimeout(() => this.#show(container.id), DELAY))
      })
    }))

    this.#updateTab()
  }

  // Still unread after the wait: whatever dot is there now shows
  #show(id) {
    this.timers.delete(id)
    document.getElementById(id)?.querySelector(".unread-dot")?.classList.remove("unread-dot--pending")
    this.#updateTab()
  }

  #cancel(id) {
    clearTimeout(this.timers.get(id))
    this.timers.delete(id)
  }

  #containersIn(node) {
    if (node.nodeType !== Node.ELEMENT_NODE) return []
    const inside = Array.from(node.querySelectorAll(CONTAINERS))
    return node.matches(CONTAINERS) ? [ node, ...inside ] : inside
  }

  #updateTab() {
    const unread = Boolean(this.element.querySelector(".server-rail .unread-dot:not(.unread-dot--pending)"))
    document.title = unread ? TITLE_DOT + this.baseTitle : this.baseTitle
    this.#setFavicon(unread)
  }

  #setFavicon(unread) {
    const links = Array.from(document.querySelectorAll("link[rel~='icon']"))
    links.forEach(link => { link.dataset.plainHref ??= link.getAttribute("href") })

    if (!unread) {
      links.forEach(link => link.setAttribute("href", link.dataset.plainHref))
      return
    }

    const source = links.find(link => link.type === "image/png") || links[0]
    if (!source) return
    badgedIcon ??= badge(source.dataset.plainHref)
    badgedIcon.then(href => {
      // Only if still unread by the time it's drawn
      if (!href || !this.element.querySelector(".server-rail .unread-dot:not(.unread-dot--pending)")) return
      links.forEach(link => link.setAttribute("href", href))
    })
  }
}

// The logo with a dot in its top-right corner, as a data: URL (null if the
// logo can't be loaded)
function badge(src) {
  return new Promise(resolve => {
    const image = new Image()
    image.onload = () => {
      const size = 64
      const canvas = document.createElement("canvas")
      canvas.width = canvas.height = size
      const context = canvas.getContext("2d")
      context.drawImage(image, 0, 0, size, size)
      context.beginPath()
      context.arc(45, 19, 17, 0, 2 * Math.PI)
      context.fillStyle = "#1d5653"
      context.fill()
      context.lineWidth = 4
      context.strokeStyle = "#3f9380"
      context.stroke()
      resolve(canvas.toDataURL("image/png"))
    }
    image.onerror = () => resolve(null)
    image.src = src
  })
}
