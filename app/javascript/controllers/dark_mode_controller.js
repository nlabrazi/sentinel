import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["icon", "text"]

  connect() {
    const isDark = localStorage.getItem("darkMode") === "true"

    document.documentElement.classList.toggle("dark", isDark)
    this.updateUI(isDark)
  }

  toggle() {
    const isDark = document.documentElement.classList.toggle("dark")

    localStorage.setItem("darkMode", isDark)
    this.updateUI(isDark)
  }

  updateUI(isDark) {
    this.iconTarget.classList.remove("fa-moon", "fa-sun")
    this.iconTarget.classList.add(isDark ? "fa-sun" : "fa-moon")

    this.textTarget.textContent = isDark
      ? "Activer Mode clair"
      : "Activer Mode sombre"
  }
}
