import { Controller } from "@hotwired/stimulus"

// Tree explorer controller for navigating nested groups and profiles.
// Handles expand/collapse of folders and lazy-loads content panels via fetch.
export default class extends Controller {
  static targets = ["content", "fallback"]

  connect() {
    // Progressive enhancement: show the interactive explorer, hide the flat fallback
    const explorer = this.element.querySelector(".explorer")
    if (explorer) explorer.classList.add("explorer--active")
    if (this.hasFallbackTarget) {
      this.fallbackTarget.hidden = true
    }
  }

  selectRoot(event) {
    const button = event.currentTarget
    this.#clearActive()
    button.classList.add("tree__item--active")
    this.#loadPanel(button.dataset.panelUrl)
  }

  selectGroup(event) {
    const button = event.currentTarget
    this.#clearActive()
    button.classList.add("tree__item--active")
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

    this.#loadPanel(panelUrl)
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
