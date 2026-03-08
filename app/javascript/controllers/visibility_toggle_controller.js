import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "form", "indicator"]

  async toggle(event) {
    const checkbox = event.target
    const hidden = checkbox.checked
    const targetType = checkbox.dataset.targetType
    const targetId = checkbox.dataset.targetId

    // Find the closest form for this checkbox
    const form = checkbox.closest(".tree-editor__toggle-form")
    if (!form) return

    // Update the hidden field value
    const hiddenField = form.querySelector('input[name="hidden"]')
    if (hiddenField) hiddenField.value = hidden ? "1" : "0"

    // Find the save indicator - it's in the .tree-editor__actions alongside the form
    const actions = checkbox.closest(".tree-editor__actions")
    const indicator = actions?.querySelector(".tree-editor__save-indicator")

    try {
      const response = await fetch(form.action, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
          "Accept": "application/json"
        },
        body: new URLSearchParams(new FormData(form))
      })

      if (response.ok) {
        this.showIndicator(indicator, "Saved", "tree-editor__save-indicator--visible", 1500)

        // Reflect hidden state on the row element so CSS shows/hides the tag
        const row = checkbox.closest(".tree-editor__leaf, .tree-editor__folder")
        if (row) row.classList.toggle("tree-editor__node--hidden", hidden)

        // Cascade: if hiding a group, disable and dim descendant checkboxes
        if (targetType === "Group") {
          const node = checkbox.closest(".tree-editor__folder")
          if (node) this.cascadeGroupVisibility(node, hidden)
        }
      } else {
        // Revert on failure
        checkbox.checked = !hidden
        this.showIndicator(indicator, "Error", "tree-editor__save-indicator--error", 2000)
      }
    } catch {
      checkbox.checked = !hidden
    }
  }

  showIndicator(indicator, text, className, duration) {
    if (!indicator) return

    indicator.textContent = text
    indicator.classList.add(className)
    setTimeout(() => {
      indicator.classList.remove(className)
    }, duration)
  }

  cascadeGroupVisibility(groupNode, hidden) {
    // Find the children container within this folder's details element
    const childrenContainer = groupNode.querySelector(".tree-editor__children")
    if (!childrenContainer) return

    // Get all descendant folders and leaves
    const descendants = childrenContainer.querySelectorAll(".tree-editor__folder, .tree-editor__leaf")
    descendants.forEach(node => {
      const cb = node.querySelector('input[type="checkbox"]')

      if (hidden) {
        node.classList.add("tree-editor__node--hidden")
        if (cb) cb.disabled = true
      } else {
        this.uncascadeNode(node, cb)
      }
    })
  }

  uncascadeNode(node, cb) {
    // Only un-cascade nodes that aren't directly hidden themselves
    if (!cb?.checked) {
      // Node is not directly hidden — remove hidden styling
      node.classList.remove("tree-editor__node--hidden")
      if (cb) cb.disabled = false
    } else {
      // Node is directly hidden — keep it hidden but re-enable its checkbox
      if (cb) cb.disabled = false
    }
  }
}
