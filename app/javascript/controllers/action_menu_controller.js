import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  closeOnOutsideClick(event) {
    if (!this.element.open || this.element.contains(event.target)) return

    this.element.open = false
  }
}
