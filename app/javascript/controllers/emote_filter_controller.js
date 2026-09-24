import { Controller } from "@hotwired/stimulus"

// Narrows the admin emote list to rows whose name, code or old codes contain
// what's typed. Rows re-rendered by a Turbo Stream are filtered as they
// arrive, so the filter survives edits.
//
// While filtering, sections (<details>) open if they have a match and close
// if they don't. Clearing the filter puts them back how they were.
export default class extends Controller {
  static targets = [ "input", "row", "section" ]

  filter() {
    this.rowTargets.forEach((row) => this.apply(row))
    this.updateSections()
  }

  rowTargetConnected(row) {
    this.apply(row)
    this.queueSectionUpdate()
  }

  sectionTargetConnected() {
    this.queueSectionUpdate()
  }

  apply(row) {
    const query = this.query
    row.hidden = query !== "" && !row.dataset.search.includes(query)
  }

  // A re-render connects every row and section at once, and the sections'
  // details-persist controllers restore their stored state as they connect,
  // so wait for all of that before opening sections.
  queueSectionUpdate() {
    if (this.sectionUpdateQueued) return
    this.sectionUpdateQueued = true
    queueMicrotask(() => {
      this.sectionUpdateQueued = false
      this.updateSections()
    })
  }

  updateSections() {
    const filtering = this.query !== ""
    this.sectionTargets.forEach((section) => {
      if (filtering) {
        if (!("openBeforeFilter" in section.dataset)) section.dataset.openBeforeFilter = section.open
        section.open = this.rowTargets.some((row) => !row.hidden && section.contains(row))
      } else if ("openBeforeFilter" in section.dataset) {
        section.open = section.dataset.openBeforeFilter === "true"
        delete section.dataset.openBeforeFilter
      }
    })
  }

  get query() {
    return this.hasInputTarget ? normalise(this.inputTarget.value) : ""
  }
}

// ":Spring Heart:" → "spring_heart", matching how names and codes are stored.
function normalise(value) {
  return value.trim().toLowerCase().replace(/^[:;]+|[:;]+$/g, "").replace(/[\s-]+/g, "_")
}
