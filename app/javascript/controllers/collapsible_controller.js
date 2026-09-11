import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "icon", "buttonLabel", "trigger"]
  static values = {
    open: { type: Boolean, default: true },
    storageKey: { type: String, default: "" }
  }

  connect() {
    if (this.storageKeyValue && typeof window !== "undefined" && window.localStorage) {
      try {
        const stored = window.localStorage.getItem(this.storageKeyValue)
        if (stored !== null) {
          this.openValue = stored === "true"
        }
      } catch (_e) {
        // Ignore storage access errors in restricted contexts
      }
    }
    this.apply()
  }

  toggle(event) {
    if (event) {
      event.preventDefault()
    }
    this.openValue = !this.openValue

    if (this.storageKeyValue && typeof window !== "undefined" && window.localStorage) {
      try {
        window.localStorage.setItem(this.storageKeyValue, String(this.openValue))
      } catch (_e) {
        // Ignore storage access errors in restricted contexts
      }
    }
    this.apply()
  }

  apply() {
    if (this.hasContentTarget) {
      this.contentTarget.classList.toggle("hidden", !this.openValue)
    }

    if (this.hasIconTarget) {
      this.iconTarget.classList.toggle("rotate-90", this.openValue)
    }

    if (this.hasButtonLabelTarget) {
      this.buttonLabelTarget.textContent = this.openValue ? "Masquer" : "Afficher"
    }

    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", String(this.openValue))
    }
  }
}
