import { Controller } from "@hotwired/stimulus"

// Adds collapse-all / expand-all behaviour for the sidebar tree.
// Place on the <details> element that wraps the sidebar tree.
// The actions find all descendant tree-node <details> elements
// (identified by data-details-persist-key-value), toggle their open
// state, and keep localStorage in sync with details-persist.
export default class extends Controller {
  expandAll() {
    this.treeDetails().forEach(el => {
      el.setAttribute("open", "")
      this.#updateStorage(el, "open")
    })
  }

  collapseAll() {
    this.treeDetails().forEach(el => {
      el.removeAttribute("open")
      this.#updateStorage(el, "closed")
    })
  }

  // All descendant <details> that belong to individual tree nodes
  // (i.e. have a details-persist key). Does not include this.element itself.
  treeDetails() {
    return Array.from(
      this.element.querySelectorAll("details[data-details-persist-key-value]")
    )
  }

  #updateStorage(el, state) {
    const key = el.dataset.detailsPersistKeyValue
    if (key) localStorage.setItem(`details-persist:${key}`, state)
  }
}
