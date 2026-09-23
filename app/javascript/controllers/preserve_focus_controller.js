import { Controller } from "@hotwired/stimulus"

// Keeps keyboard focus in place when a Turbo Stream replaces the content that
// holds it: afterwards, focus moves to the element with the same id in the
// new content, with the caret where it was. Without this, re-rendering a list
// after each edit would drop focus to the top of the page.
export default class extends Controller {
  connect() {
    this.wrapRender = this.wrapRender.bind(this)
    document.addEventListener("turbo:before-stream-render", this.wrapRender)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.wrapRender)
  }

  wrapRender(event) {
    const active = document.activeElement
    if (!active?.id || !this.element.contains(active)) return

    const id = active.id
    const selection = hasTextSelection(active) ? [ active.selectionStart, active.selectionEnd ] : null
    const render = event.detail.render

    event.detail.render = async (streamElement) => {
      await render(streamElement)

      const replacement = document.getElementById(id)
      if (!replacement || replacement === active || !this.element.contains(replacement)) return

      replacement.focus()
      if (selection && hasTextSelection(replacement)) replacement.setSelectionRange(...selection)
    }
  }
}

function hasTextSelection(element) {
  return element instanceof HTMLInputElement && [ "text", "search" ].includes(element.type)
}
