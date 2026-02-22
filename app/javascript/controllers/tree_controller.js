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
    const button = event.currentTarget
    this.#clearActive()
    button.classList.add("tree__item--active")
    history.replaceState(null, "", window.location.pathname)
    this.#loadPanel(button.dataset.panelUrl)
  }

  selectGroup(event) {
    const button = event.currentTarget
    this.#clearActive()
    button.classList.add("tree__item--active")
    this.#setHash("group", button.dataset.groupUuid)
    this.#loadPanel(button.dataset.panelUrl)
  }

  toggleFolder(event) {
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
    const button = event.currentTarget
    this.#selectProfileButton(button)
  }

  selectProfileCard(event) {
    event.preventDefault()
    const link = event.currentTarget
    this.#selectProfileButton(link)
  }

  // --- private ---

  #selectProfileButton(button) {
    const { panelUrl, groupUuid, profileUuid } = button.dataset

    this.#clearActive()

    // Highlight the matching leaf in the tree
    const treeLeaf = this.element.querySelector(
      `.tree button[data-group-uuid="${groupUuid}"][data-profile-uuid="${profileUuid}"]`
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
    this.#loadPanel(panelUrl)
  }

  #restoreFromHash() {
    const hash = window.location.hash.slice(1)
    if (!hash) return

    const parts = hash.split("/")

    if (parts[0] === "group" && parts[1]) {
      const button = this.element.querySelector(
        `.tree button[data-action*="selectGroup"][data-group-uuid="${parts[1]}"],
         .tree button[data-action*="selectRoot"][data-group-uuid="${parts[1]}"]`
      )
      if (button) {
        this.#clearActive()
        button.classList.add("tree__item--active")
        this.#loadPanel(button.dataset.panelUrl)
      }
    } else if (parts[0] === "profile" && parts[1] && parts[2]) {
      const button = this.element.querySelector(
        `.tree button[data-group-uuid="${parts[1]}"][data-profile-uuid="${parts[2]}"]`
      )
      if (button) {
        this.#selectProfileButton(button)
      }
    }
  }

  #setHash(type, ...uuids) {
    history.replaceState(null, "", `#${type}/${uuids.join("/")}`)
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
