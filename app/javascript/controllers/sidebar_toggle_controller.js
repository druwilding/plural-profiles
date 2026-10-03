import { Controller } from "@hotwired/stimulus"

// Hides and shows the sidebar beside the main content, so the content can
// use the whole width. The choice is kept in a cookie, which the server reads
// (ApplicationHelper#sidebar_hidden?) to render every page that way from the
// start. Place on the .layout element that holds the sidebar.
export default class extends Controller {
  static targets = ["sidebar", "hideButton", "showButton"]

  connect() {
    // A page Turbo restores from its cache may predate the latest choice.
    this.#apply(document.cookie.split("; ").includes("sidebar=hidden"))
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
    document.cookie = `sidebar=${hidden ? "hidden" : "shown"}; path=/; max-age=31536000; SameSite=Lax`
    this.#apply(hidden)
  }

  #apply(hidden) {
    this.element.classList.toggle("layout--sidebar-hidden", hidden)
    this.sidebarTarget.hidden = hidden
    this.showButtonTarget.hidden = !hidden
  }
}
