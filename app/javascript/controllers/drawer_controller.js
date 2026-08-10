import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.scrollToBottom()
    this.keydown = (event) => { if (event.key === "Escape") this.close() }
    document.addEventListener("keydown", this.keydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.keydown)
  }

  close() {
    const frame = this.element.closest("turbo-frame")
    frame.removeAttribute("src")
    frame.innerHTML = ""
  }

  scrollToBottom() {
    const lines = this.element.querySelector(".log-lines")
    if (lines) lines.scrollTop = lines.scrollHeight
  }
}
