import { Controller } from "@hotwired/stimulus"

// Chat message pane: starts scrolled to the newest message, follows new
// messages as they arrive via Turbo Stream broadcast (but only while the
// reader is already at/near the bottom, so reading history doesn't get
// yanked back down from under them), and keeps the reader's position steady
// when older history loads in above them as they scroll up — without this,
// the browser's default scroll-anchoring isn't reliable enough here, and the
// reader lands at the top of each newly-loaded batch, which immediately
// triggers loading the next one, cascading all the way back through history.
export default class extends Controller {
  static targets = ["scrollable", "messages"]

  connect() {
    this.stickToBottom = true
    this.scrollToBottom()

    this.onScroll = this.onScroll.bind(this)
    this.scrollableTarget.addEventListener("scroll", this.onScroll, { passive: true })

    this.onBeforeFrameRender = this.onBeforeFrameRender.bind(this)
    this.scrollableTarget.addEventListener("turbo:before-frame-render", this.onBeforeFrameRender)

    this.onFrameLoad = this.onFrameLoad.bind(this)
    this.scrollableTarget.addEventListener("turbo:frame-load", this.onFrameLoad)

    this.observer = new MutationObserver(this.onMessagesChanged.bind(this))
    this.observer.observe(this.messagesTarget, { childList: true })

    // The pane changes size when a phone's keyboard opens (the page shrinks
    // to the space above it) or the composer grows as a message gets longer.
    // Shrinking keeps the scroll position, which would hide the newest
    // messages under the composer just as someone goes to reply to them, so
    // a reader at the bottom stays at the bottom.
    this.resizeObserver = new ResizeObserver(() => {
      if (this.stickToBottom) this.scrollToBottom()
    })
    this.resizeObserver.observe(this.scrollableTarget)
  }

  disconnect() {
    this.scrollableTarget.removeEventListener("scroll", this.onScroll)
    this.scrollableTarget.removeEventListener("turbo:before-frame-render", this.onBeforeFrameRender)
    this.scrollableTarget.removeEventListener("turbo:frame-load", this.onFrameLoad)
    this.observer?.disconnect()
    this.resizeObserver?.disconnect()
  }

  onScroll() {
    const el = this.scrollableTarget
    this.stickToBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 150
  }

  // Anchor on the first already-rendered message/divider — a sibling of the
  // lazy-load frame that this mutation never touches, just visually pushes
  // down. Measuring exactly how far *that specific element* moves and
  // compensating for precisely that is self-correcting regardless of how
  // much content actually loaded, unlike diffing raw scrollHeight before vs.
  // after (which turned out to overshoot badly — likely a timing mismatch
  // between when scrollHeight was read and when the browser had actually
  // finished laying out the new content).
  onBeforeFrameRender() {
    this.scrollAnchor = this.messagesTarget.querySelector(".chat-message, .chat-date-divider")
    this.scrollAnchorTop = this.scrollAnchor?.getBoundingClientRect().top
  }

  onFrameLoad() {
    if (!this.scrollAnchor || this.scrollAnchorTop == null) return

    const newTop = this.scrollAnchor.getBoundingClientRect().top
    this.scrollableTarget.scrollTop += newTop - this.scrollAnchorTop
    this.scrollAnchor = null
    this.scrollAnchorTop = null
  }

  onMessagesChanged(mutations) {
    // childList (non-subtree) mutations on #chat-messages only fire for new
    // messages appended at the end — older history loads into the nested
    // turbo-frame's own subtree, not as a direct child here.
    const appendedAtEnd = mutations.some((mutation) =>
      Array.from(mutation.addedNodes).some((node) => node === this.messagesTarget.lastElementChild)
    )
    if (appendedAtEnd && this.stickToBottom) this.scrollToBottom()
  }

  scrollToBottom() {
    this.scrollableTarget.scrollTop = this.scrollableTarget.scrollHeight
  }
}
