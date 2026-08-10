import { Controller } from "@hotwired/stimulus"

// Live tail over SSE. Appended lines respect the active search filter via
// the follow:appended event; the view stays pinned to the bottom unless the
// user has scrolled up.
export default class extends Controller {
  static targets = ["button", "lines"]
  static values = { url: String }

  toggle() {
    this.source ? this.stop() : this.start()
  }

  start() {
    this.source = new EventSource(this.urlValue)
    this.source.onmessage = (event) => this.append(event.data)
    this.source.addEventListener("closed", () => this.stop())
    this.buttonTarget.textContent = "pause"
    this.buttonTarget.classList.add("following")
  }

  stop() {
    if (this.source) this.source.close()
    this.source = null
    if (this.hasButtonTarget) {
      this.buttonTarget.textContent = "follow"
      this.buttonTarget.classList.remove("following")
    }
  }

  append(html) {
    const template = document.createElement("template")
    template.innerHTML = html
    const lines = this.linesTarget
    const pinned = lines.scrollHeight - lines.scrollTop - lines.clientHeight < 60
    lines.append(template.content)
    if (pinned) lines.scrollTop = lines.scrollHeight
    this.dispatch("appended")
  }

  disconnect() {
    this.stop()
  }
}
