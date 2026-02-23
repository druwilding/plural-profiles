import { Controller } from "@hotwired/stimulus"

// Tree explorer controller for navigating nested groups and profiles.
// Handles expand/collapse of folders, lazy-loads content panels via fetch,
// and updates the URL hash for permalink sharing.
//
// Hash formats:
//   #group/{uuid}                — selects a sub-group
//   #profile/{groupUuid}/{uuid}  — selects a profile within a group
//   (no hash)                    — shows the root group
export default class extends Controller {
  static targets = ["content", "fallback"]

  connect() {
    // Progressive enhancement: show the interactive explorer, hide the flat fallback
    const explorer = this.element.querySelector(".explorer")
    if (explorer) explorer.classList.add("explorer--active")
    if (this.hasFallbackTarget) {
      this.fallbackTarget.hidden = true
    }

    this.#restoreFromHash()
  }

  selectRoot(event) {
    event.preventDefault()
    const link = event.currentTarget
    this.#clearActive()
    link.classList.add("tree__item--active")
    history.replaceState(null, "", window.location.pathname + window.location.search)
    this.#loadPanelAndScroll(link.dataset.panelUrl)
  }

  selectGroup(event) {
    event.preventDefault()
    const link = event.currentTarget
    this.#clearActive()
    link.classList.add("tree__item--active")
    this.#setHash("group", link.dataset.groupUuid)
    this.#loadPanelAndScroll(link.dataset.panelUrl)
  }

  toggleFolder(event) {
    if (event.type === "keydown") {
      if (event.key !== "Enter" && event.key !== " ") return
      event.preventDefault()
    }
    const button = event.currentTarget
    const folder = button.closest(".tree__folder")
    const children = folder?.querySelector(".tree__children")
    if (!children) return

    const isHidden = children.style.display === "none"
    children.style.display = isHidden ? "" : "none"
    folder.setAttribute("aria-expanded", isHidden)
    const arrow = button.querySelector(".tree__arrow")
    if (arrow) {
      arrow.classList.toggle("tree__arrow--open", isHidden)
    }
  }

  selectProfile(event) {
    event.preventDefault()
    const link = event.currentTarget
    this.#selectProfileButton(link)
  }

  selectProfileCard(event) {
    event.preventDefault()
    const link = event.currentTarget
    this.#selectProfileButton(link)
  }

  // --- private ---

  #selectProfileButton(link) {
    const { panelUrl, groupUuid, profileUuid } = link.dataset

    this.#clearActive()

    // Highlight the matching leaf in the tree
    const treeLeaf = this.element.querySelector(
      `.tree .tree__item[data-group-uuid="${groupUuid}"][data-profile-uuid="${profileUuid}"]`
    )
    if (treeLeaf) {
      treeLeaf.classList.add("tree__item--active")
      // Ensure parent folders are expanded so the leaf is visible
      let parent = treeLeaf.closest(".tree__children")
      while (parent) {
        parent.style.display = ""
        const folder = parent.closest(".tree__folder")
        if (folder) folder.setAttribute("aria-expanded", "true")
        const arrowBtn = parent.previousElementSibling?.querySelector(".tree__arrow")
        if (arrowBtn) arrowBtn.classList.add("tree__arrow--open")
        parent = parent.parentElement?.closest(".tree__children")
      }
    }

    this.#setHash("profile", groupUuid, profileUuid)
    this.#loadPanelAndScroll(panelUrl)
  }

  #restoreFromHash() {
    const hash = window.location.hash.slice(1)
    if (!hash) return

    const parts = hash.split("/")

    if (parts[0] === "group" && parts[1]) {
      const link = this.element.querySelector(
        `.tree .tree__item[data-action*="selectGroup"][data-group-uuid="${parts[1]}"],
         .tree .tree__item[data-action*="selectRoot"][data-group-uuid="${parts[1]}"]`
      )
      if (link) {
        this.#clearActive()
        link.classList.add("tree__item--active")
        this.#loadPanelAndScroll(link.dataset.panelUrl)
      }
    } else if (parts[0] === "profile" && parts[1] && parts[2]) {
      const link = this.element.querySelector(
        `.tree .tree__item[data-group-uuid="${parts[1]}"][data-profile-uuid="${parts[2]}"]`
      )
      if (link) {
        this.#selectProfileButton(link)
      }
    }
  }

  #setHash(type, ...uuids) {
    history.replaceState(null, "", `#${type}/${uuids.join("/")}`)
  }

  async #loadPanelAndScroll(url) {
    await this.#loadPanel(url)
    this.contentTarget.scrollIntoView({ behavior: "smooth", block: "start" })
  }

  async #loadPanel(url) {
    if (!url) return

    try {
      const response = await fetch(url, {
        headers: { "X-Requested-With": "XMLHttpRequest" }
      })
      if (response.ok) {
        this.contentTarget.innerHTML = await response.text()
      }
    } catch (error) {
      // Silently fail — content panel stays as-is
    }
  }

  #clearActive() {
    this.element.querySelectorAll(".tree__item--active").forEach(el => {
      el.classList.remove("tree__item--active")
    })
  }
}
