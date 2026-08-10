import { Controller } from "@hotwired/stimulus"

// Instant client-side filter over the loaded log window — no round-trips.
export default class extends Controller {
  static targets = ["input", "count", "lines"]

  filter() {
    const query = this.inputTarget.value.toLowerCase()
    const lines = this.linesTarget.querySelectorAll(".log-line")
    let shown = 0

    lines.forEach((line) => {
      const match = query === "" || line.textContent.toLowerCase().includes(query)
      line.hidden = !match
      if (match) shown++
    })

    this.countTarget.textContent = query === "" ? "" : `${shown} of ${lines.length}`
  }

  clear() {
    this.inputTarget.value = ""
    this.filter()
  }

  keydown(event) {
    if (event.key === "Escape" && this.inputTarget.value !== "") {
      event.stopPropagation()
      this.clear()
    }
  }
}
