import { Controller } from "@hotwired/stimulus"

// Tree explorer controller for navigating nested groups and profiles.
// Handles expand/collapse of folders and swapping the content panel.
export default class extends Controller {
  static targets = ["content", "folder", "groupTemplate", "profileTemplate"]

  selectRoot(event) {
    const button = event.currentTarget
    this.#clearActive()
    button.classList.add("tree__item--active")

    // Show root group content
    const template = this.groupTemplateTargets[this.groupTemplateTargets.length - 1]
    if (template) {
      this.contentTarget.innerHTML = template.innerHTML
    }
  }

  selectGroup(event) {
    const button = event.currentTarget
    const { groupUuid } = button.dataset

    this.#clearActive()
    button.classList.add("tree__item--active")

    const template = this.groupTemplateTargets.find(
      t => t.dataset.groupUuid === groupUuid
    )
    if (template) {
      this.contentTarget.innerHTML = template.innerHTML
    }
  }

  toggleFolder(event) {
    const button = event.currentTarget
    const folder = button.closest(".tree__folder")
    const children = folder?.querySelector(".tree__children")
    if (!children) return

    const isHidden = children.style.display === "none"
    children.style.display = isHidden ? "" : "none"
    const arrow = button.querySelector(".tree__arrow")
    if (arrow) {
      arrow.classList.toggle("tree__arrow--open", isHidden)
    }
  }

  selectProfile(event) {
    const button = event.currentTarget
    const { groupUuid, profileUuid } = button.dataset

    this.#clearActive()
    button.classList.add("tree__item--active")

    const template = this.profileTemplateTargets.find(
      t => t.dataset.groupUuid === groupUuid && t.dataset.profileUuid === profileUuid
    )
    if (template) {
      this.contentTarget.innerHTML = template.innerHTML
    }
  }

  // --- private ---

  #clearActive() {
    this.element.querySelectorAll(".tree__item--active").forEach(el => {
      el.classList.remove("tree__item--active")
    })
  }
}
