import { Controller } from "@hotwired/stimulus"

// Tree explorer controller for navigating nested groups and profiles.
// Handles expand/collapse of folders and swapping the content panel.
export default class extends Controller {
  static targets = ["content", "folder", "groupTemplate", "profileTemplate"]

  selectRoot(event) {
    const button = event.currentTarget
    this.#clearActive()
    button.classList.add("tree__toggle--active")

    // Toggle children visibility
    const children = button.nextElementSibling
    if (children) {
      const isHidden = children.style.display === "none"
      children.style.display = isHidden ? "" : "none"
      this.#rotateArrow(button, isHidden)
    }

    // Show root group content
    const rootTemplate = this.groupTemplateTargets.find(
      t => t.dataset.groupUuid === this.element.querySelector("[data-group-uuid]")?.dataset.groupUuid
    )
    // Use the last groupTemplate (root) as fallback
    const template = rootTemplate || this.groupTemplateTargets[this.groupTemplateTargets.length - 1]
    if (template) {
      this.contentTarget.innerHTML = template.innerHTML
    }
  }

  toggleFolder(event) {
    const button = event.currentTarget
    const children = button.nextElementSibling
    if (!children) return

    const isHidden = children.style.display === "none"
    children.style.display = isHidden ? "" : "none"
    this.#rotateArrow(button, isHidden)
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
    this.element.querySelectorAll(".tree__toggle--active, .tree__item--active").forEach(el => {
      el.classList.remove("tree__toggle--active", "tree__item--active")
    })
  }

  #rotateArrow(button, open) {
    const arrow = button.querySelector(".tree__arrow")
    if (arrow) {
      arrow.style.transform = open ? "rotate(90deg)" : ""
    }
  }
}
