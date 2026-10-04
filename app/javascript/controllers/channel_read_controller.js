import { Controller } from "@hotwired/stimulus"

// Marks the channel as read once this page has actually mounted into the
// DOM, and again every time a new message streams in live while it's still
// open. Deliberately not a side effect of the channel's own GET request --
// Turbo 8 prefetches links on hover, and a GET that marks the channel read
// would silently clear the unread dot the moment a pointer passed over the
// sidebar link, before the reader ever opened it. connect() only fires on a
// genuine Turbo visit (prefetch caches the response but never inserts it
// into the document, so Stimulus never connects to it).
//
// Re-marking on every live message matters for the server-rail dot
// specifically: the server broadcasts an optimistic "unread" the moment
// anyone else posts, with no way to know the recipient is actually looking
// right at that channel. Without this, the rail icon would light up even
// while you're mid-conversation in the very channel that caused it. Chasing
// each new message with a fresh read marker keeps that self-correcting
// (chat_unread_controller.js holds a new dot back long enough to hide the
// round trip) without needing real presence tracking.
//
// Only while someone could be reading, though: the tab in view and the window
// focused. A message that arrives while they're in another tab or another
// app stays unread, so its dot (and the tab's) can tell them about it; the
// channel's marked read when they come back. The same goes for a page that
// loads in the background, such as a link opened in a new tab.
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.markReadIfSeen()

    const messages = this.element.querySelector("#chat-messages")
    if (messages) {
      this.observer = new MutationObserver(() => this.markReadIfSeen())
      this.observer.observe(messages, { childList: true })
    }

    this.cameBack = this.cameBack.bind(this)
    document.addEventListener("visibilitychange", this.cameBack)
    window.addEventListener("focus", this.cameBack)
  }

  disconnect() {
    this.observer?.disconnect()
    document.removeEventListener("visibilitychange", this.cameBack)
    window.removeEventListener("focus", this.cameBack)
  }

  markReadIfSeen() {
    if (this.#seen()) {
      this.pending = false
      this.markRead()
    } else {
      this.pending = true
    }
  }

  // Back in the tab or window, with something left to mark
  cameBack() {
    if (this.pending) this.markReadIfSeen()
  }

  markRead() {
    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        "Accept": "text/plain"
      }
    })
  }

  #seen() {
    return document.visibilityState === "visible" && document.hasFocus()
  }
}
