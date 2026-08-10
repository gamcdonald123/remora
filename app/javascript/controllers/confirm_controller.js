import { Controller } from "@hotwired/stimulus"

// Two-click inline confirm: first submit arms the button, second one goes through.
export default class extends Controller {
  intercept(event) {
    if (this.armed) return

    event.preventDefault()
    this.armed = true
    const button = this.element.querySelector("button")
    this.originalText = button.textContent
    button.textContent = "sure?"
    button.classList.add("armed")
    this.timeout = setTimeout(() => this.reset(button), 3000)
  }

  reset(button) {
    this.armed = false
    button.textContent = this.originalText
    button.classList.remove("armed")
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
