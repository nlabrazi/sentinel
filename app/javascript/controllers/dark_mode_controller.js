import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["icon", "text"]

  connect() {
    const isDark = localStorage.getItem('darkMode') === 'true'

    document.documentElement.classList.toggle('dark', isDark)
    this.updateUI(isDark)
  }

  toggle() {
    const isDark = document.documentElement.classList.toggle('dark')
    localStorage.setItem('darkMode', isDark)
    this.updateUI(isDark)
  }

  updateUI(isDark) {
    if (isDark) {
      this.iconTarget.innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" />'
      this.textTarget.textContent = 'Activer Mode clair'
    } else {
      this.iconTarget.innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z" />'
      this.textTarget.textContent = 'Activer Mode sombre'
    }
  }
}
