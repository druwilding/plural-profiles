import { Controller } from "@hotwired/stimulus"

// A line of text cut short with an ellipsis, with a "more" button to show it
// in full. The button only appears while something is actually cut short,
// and is a real button, so the full text is there for keyboard and touch
// users as well as for a mouse hovering over the title tooltip.
//
// Screen readers get the full text either way: an ellipsis only hides it
// visually.
//
// Targets: "text" for each part that can be cut short, "toggle" for the button
// (with a "label" inside it). The element gets the expandedClass while open.
export default class extends Controller {
  static targets = [ "text", "toggle", "label" ]
  static classes = [ "expanded" ]

  connect() {
    this.expanded = false
    this.observer = new ResizeObserver(() => this.update())
    this.textTargets.forEach(text => this.observer.observe(text))
    this.update()
  }

  disconnect() {
    this.observer.disconnect()
  }

  toggle() {
    this.expanded = !this.expanded
    this.element.classList.toggle(this.expandedClass, this.expanded)
    this.toggleTarget.setAttribute("aria-expanded", this.expanded)
    this.labelTarget.textContent = this.expanded ? "less" : "more"
    this.update()
  }

  // Shown while open (to close it again), or while anything is cut short
  update() {
    const cutShort = this.textTargets.some(text => text.scrollWidth > text.clientWidth)
    this.toggleTarget.hidden = !this.expanded && !cutShort
  }
}
