import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "form", "indicator"]

  connect() {
    this.element.querySelectorAll(".tree-editor__hide-label").forEach(label => {
      label.removeAttribute("hidden")
    })
  }

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

        // Cascade: only if this group is rendered as a folder (has children).
        // If it's a leaf we have nothing to cascade into, and climbing to the
        // nearest ancestor folder would wrongly affect siblings.
        if (targetType === "Group" && row?.classList.contains("tree-editor__folder")) {
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
    const childrenContainer = groupNode.querySelector(".tree-editor__children")
    if (!childrenContainer) return

    if (hidden) {
      // Cascade hidden: mark every descendant node as hidden and disable its checkbox.
      childrenContainer.querySelectorAll(".tree-editor__leaf, .tree-editor__folder").forEach(node => {
        node.classList.add("tree-editor__node--hidden")
      })
      childrenContainer.querySelectorAll('input[type="checkbox"]').forEach(cb => {
        cb.disabled = true
        cb.setAttribute("aria-disabled", "true")
      })
    } else {
      // Cascade un-hidden: walk direct children, removing the hidden class
      // and re-enabling checkboxes only for nodes that aren't directly hidden
      // themselves. Stop recursing into any node that is directly hidden so
      // its own subtree is left untouched.
      this._uncascadeChildren(childrenContainer)
    }
  }

  _uncascadeChildren(container) {
    container.querySelectorAll(":scope > .tree-editor__leaf, :scope > .tree-editor__folder").forEach(node => {
      const isFolder = node.tagName === "DETAILS"

      // Locate the checkbox that belongs to *this* node, not a descendant.
      // For folders the checkbox lives in the <summary>'s actions bar;
      // for leaves the leaf itself has no children so any match is fine.
      const checkbox = isFolder
        ? node.querySelector("summary .tree-editor__actions input[type='checkbox']")
        : node.querySelector(".tree-editor__actions input[type='checkbox']")

      if (checkbox?.checked) {
        // This node is directly hidden — leave it and its subtree alone,
        // but re-enable its own checkbox so the user can unhide it later.
        if (checkbox) {
          checkbox.disabled = false
          checkbox.removeAttribute("aria-disabled")
        }
        return
      }

      // Not directly hidden: remove the cascade class and re-enable.
      node.classList.remove("tree-editor__node--hidden")
      if (checkbox) {
        checkbox.disabled = false
        checkbox.removeAttribute("aria-disabled")
      }

      // Recurse into folder children.
      if (isFolder) {
        const children = node.querySelector(".tree-editor__children")
        if (children) this._uncascadeChildren(children)
      }
    })
  }
}
