import { Controller } from "@hotwired/stimulus"

// Hides and shows a sidebar beside the main content, so the content can use
// the whole width. The choice is kept in a cookie, which the server reads
// (ApplicationHelper#sidebar_hidden?) to render every page that way from the
// start. Place on the element holding the sidebar and the content, with the
// cookie's name (each kind of sidebar remembers its own choice) and the class
// that gives the content the sidebar's room.
export default class extends Controller {
  static targets = ["sidebar", "hideButton", "showButton"]
  static values = { cookie: String }
  static classes = ["hidden"]

  connect() {
    // A page Turbo restores from its cache may predate the latest choice.
    this.#apply(document.cookie.split("; ").includes(`${this.cookieValue}=hidden`))
  }

  hide() {
    this.#save(true)
    this.showButtonTarget.focus()
  }

  show() {
    this.#save(false)
    this.hideButtonTarget.focus()
  }

  #save(hidden) {
    document.cookie = `${this.cookieValue}=${hidden ? "hidden" : "shown"}; path=/; max-age=31536000; SameSite=Lax`
    this.#apply(hidden)
  }

  #apply(hidden) {
    this.element.classList.toggle(this.hiddenClass, hidden)
    this.sidebarTarget.hidden = hidden
    this.showButtonTarget.hidden = !hidden
  }
}
