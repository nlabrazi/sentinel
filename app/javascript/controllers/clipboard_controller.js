import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "button", "feedback"]

  copy() {
    const text = this.sourceTarget.innerText || this.sourceTarget.value || ""
    navigator.clipboard.writeText(text).then(() => {
      if (this.hasFeedbackTarget) {
        this.feedbackTarget.classList.remove("hidden")
        setTimeout(() => {
          this.feedbackTarget.classList.add("hidden")
        }, 2000)
      }
    })
  }
}
