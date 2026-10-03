import { Controller } from "@hotwired/stimulus"

// Hides and shows a sidebar beside the main content, so the content can use
// the whole width. The choice is kept in a cookie, which the server reads
// (ApplicationHelper#sidebar_hidden?) to render every page with the hidden
// class from the start. Place on the element holding the sidebar and the
// content, with the cookie's name (each kind of sidebar remembers its own
// choice) and the hidden class.
//
// CSS does the hiding, and only on html.js: without JavaScript nothing could
// bring the sidebar back, so it always shows and the buttons don't.
export default class extends Controller {
  static targets = ["hideButton", "showButton"]
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
  }
}
