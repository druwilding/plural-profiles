import { Controller } from "@hotwired/stimulus"

// Narrows the admin emote list to rows whose name, code or old codes contain
// what's typed. Rows re-rendered by a Turbo Stream are filtered as they
// arrive, so the filter survives edits.
export default class extends Controller {
  static targets = [ "input", "row" ]

  filter() {
    this.rowTargets.forEach((row) => this.apply(row))
  }

  rowTargetConnected(row) {
    this.apply(row)
  }

  apply(row) {
    const query = this.hasInputTarget ? normalise(this.inputTarget.value) : ""
    row.hidden = query !== "" && !row.dataset.search.includes(query)
  }
}

// ":Spring Heart:" → "spring_heart", matching how names and codes are stored.
function normalise(value) {
  return value.trim().toLowerCase().replace(/^[:;]+|[:;]+$/g, "").replace(/[\s-]+/g, "_")
}
