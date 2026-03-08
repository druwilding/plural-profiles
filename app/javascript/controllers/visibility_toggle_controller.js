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

    // Find the save indicator for this row
    const row = checkbox.closest(".tree-editor__node")
    const indicator = row?.querySelector(":scope > .tree-editor__row .tree-editor__save-indicator")

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

        // Cascade: if hiding a group, disable and dim descendant checkboxes
        if (targetType === "Group") {
          this.cascadeGroupVisibility(row, hidden)
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
    const childList = groupNode.querySelector(":scope > .tree-editor__children")
    if (!childList) return

    const descendantNodes = childList.querySelectorAll(".tree-editor__node")
    descendantNodes.forEach(node => {
      const cb = node.querySelector(':scope > .tree-editor__row input[type="checkbox"]')
      const tag = node.querySelector(":scope > .tree-editor__row .tree-editor__tag--hidden")

      if (hidden) {
        node.classList.add("tree-editor__node--hidden")
        if (cb) cb.disabled = true
        if (!tag) {
          const newTag = document.createElement("span")
          newTag.className = "tree-editor__tag tree-editor__tag--hidden"
          newTag.textContent = "hidden"
          const label = node.querySelector(":scope > .tree-editor__row .tree-editor__checkbox-label")
          if (label) label.appendChild(newTag)
        }
      } else {
        this.uncascadeNode(node, cb, tag)
      }
    })
  }

  uncascadeNode(node, cb, tag) {
    // Only un-cascade nodes that aren't directly hidden themselves
    if (!cb?.checked) {
      // Node is not directly hidden — remove hidden styling
      node.classList.remove("tree-editor__node--hidden")
      if (cb) cb.disabled = false
      if (tag) tag.remove()
    } else {
      // Node is directly hidden — keep it hidden but re-enable its checkbox
      if (cb) cb.disabled = false
    }
  }
}
