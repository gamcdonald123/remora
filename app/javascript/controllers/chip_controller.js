import { Controller } from "@hotwired/stimulus"

// Port chips resolve their host from wherever the user is browsing —
// tailnet name, LAN name, or IP all just work.
export default class extends Controller {
  static values = { port: Number, scheme: String }

  connect() {
    this.element.href = `${this.schemeValue}://${window.location.hostname}:${this.portValue}`
  }
}
