import { Controller } from "@hotwired/stimulus"

// Adds a date divider before a message that arrives live (the channel's
// broadcast) on a different day from the message before it, such as the
// first message in an empty channel, or the first after midnight.
//
// Dividers are otherwise drawn by the server (chat/messages/_message_list),
// in the viewer's time zone. A broadcast is drawn once for everyone, so it
// can't know whose day it is: this works it out here instead, in the same
// time zone the server used for the rest of the page (the zone value), with
// the same labels.
export default class extends Controller {
  static values = { timeZone: String }

  connect() {
    this.observer = new MutationObserver(mutations => this.#added(mutations))
    this.observer.observe(this.element, { childList: true })
  }

  disconnect() {
    this.observer.disconnect()
  }

  #added(mutations) {
    mutations.forEach(mutation => {
      mutation.addedNodes.forEach(node => {
        if (node.nodeType === Node.ELEMENT_NODE && node.matches(".chat-message")) this.#divide(node)
      })
    })
  }

  #divide(message) {
    const day = this.#day(message)
    if (!day) return

    const previous = this.#previousMessage(message)
    if (previous && this.#day(previous) === day) return
    // Already has one (it arrived again, say)
    if (message.previousElementSibling?.matches(".chat-date-divider")) return

    const divider = document.createElement("div")
    divider.className = "chat-date-divider"
    const label = document.createElement("span")
    label.textContent = this.#label(day)
    divider.append(label)
    message.before(divider)
  }

  #previousMessage(message) {
    let sibling = message.previousElementSibling
    while (sibling && !sibling.matches(".chat-message")) sibling = sibling.previousElementSibling
    return sibling
  }

  // "YYYY-MM-DD" in the viewer's time zone
  #day(message) {
    const datetime = message.querySelector("time[datetime]")?.getAttribute("datetime")
    return datetime ? this.#dayOf(new Date(datetime)) : null
  }

  #dayOf(date) {
    return new Intl.DateTimeFormat("en-CA", {
      timeZone: this.timeZoneValue || undefined,
      year: "numeric",
      month: "2-digit",
      day: "2-digit"
    }).format(date)
  }

  // As ApplicationHelper#chat_date_divider_label
  #label(day) {
    const today = this.#dayOf(new Date())
    const [ year, month, date ] = today.split("-").map(Number)
    const yesterday = new Date(Date.UTC(year, month - 1, date - 1)).toISOString().slice(0, 10)
    if (day === today) return "Today"
    if (day === yesterday) return "Yesterday"

    const [ y, m, d ] = day.split("-").map(Number)
    const parts = new Intl.DateTimeFormat("en-GB", {
      timeZone: "UTC",
      weekday: "long",
      day: "numeric",
      month: "long",
      year: "numeric"
    }).formatToParts(new Date(Date.UTC(y, m - 1, d)))
    const part = type => parts.find(p => p.type === type).value
    return `${part("weekday")}, ${part("day")} ${part("month")} ${part("year")}`
  }
}
