import { Controller } from "@hotwired/stimulus"

// Toggles spoiler text visibility on click or keyboard activation.
// Connects automatically to any element with data-controller="spoiler".
export default class extends Controller {
  toggle(event) {
    const span = event.target.closest(".spoiler")
    if (!span) return

    const revealed = span.classList.toggle("spoiler--revealed")
    span.setAttribute("aria-expanded", String(revealed))
    span.setAttribute("aria-label", revealed ? "Content revealed, click to hide" : "Hidden content, click to reveal")
  }

  keydown(event) {
    if (event.key !== "Enter" && event.key !== " ") return
    if (!event.target.closest(".spoiler")) return

    event.preventDefault()
    this.toggle(event)
  }
}
