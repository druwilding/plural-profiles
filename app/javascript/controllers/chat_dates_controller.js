import { Controller } from "@hotwired/stimulus"

// Dates and times for messages that arrive live (the channel's broadcast),
// in the viewer's time zone.
//
// The server draws everything else in the viewer's time zone. A broadcast is
// drawn once for everyone, in the sender's request, so its time is the
// sender's and it can't know whose day it is. For each live message, this
// rewrites its time, and adds a date divider before it if it's on a different
// day from the message before it (the first in an empty channel, or the first
// after midnight). Both use the time zone the server used for the rest of the
// page (the zone value), and the same formats.
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
        if (node.nodeType !== Node.ELEMENT_NODE || !node.matches(".chat-message")) return
        this.#localizeTime(node)
        this.#divide(node)
      })
    })
  }

  // As the server's %H:%M
  #localizeTime(message) {
    const time = message.querySelector("time.chat-message__time[datetime]")
    if (!time) return

    time.textContent = new Intl.DateTimeFormat("en-GB", {
      timeZone: this.timeZoneValue || undefined,
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23"
    }).format(new Date(time.getAttribute("datetime")))
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
