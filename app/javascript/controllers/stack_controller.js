import { Controller } from "@hotwired/stimulus"

// Expand/collapse a stack's member rows. State lives in sessionStorage so
// it survives the full-fleet Turbo Stream re-renders.
const KEY = "remora-expanded-stacks"

export default class extends Controller {
  static values = { name: String }

  connect() {
    if (this.expanded().has(this.nameValue)) this.apply(true)
  }

  toggle(event) {
    if (event.target.closest("a, button, form")) return

    const set = this.expanded()
    const nowOpen = !this.element.classList.contains("expanded")
    nowOpen ? set.add(this.nameValue) : set.delete(this.nameValue)
    sessionStorage.setItem(KEY, JSON.stringify([...set]))
    this.apply(nowOpen)
  }

  apply(open) {
    this.element.classList.toggle("expanded", open)
    const row = this.element.querySelector(".stack-row")
    if (row) row.setAttribute("aria-expanded", open)
  }

  expanded() {
    try {
      return new Set(JSON.parse(sessionStorage.getItem(KEY) || "[]"))
    } catch {
      return new Set()
    }
  }
}
