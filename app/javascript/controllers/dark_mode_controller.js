import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["icon", "text"]

  static icons = {
    sun: {
      viewBox: "0 0 512 512",
      path: "M361.5 1.2c5 2.1 8.6 6.6 9.6 11.9L391 121l107.9 19.8c5.3 1 9.8 4.6 11.9 9.6s1.5 10.7-1.6 15.2L446.9 256l62.3 90.3c3.1 4.5 3.7 10.2 1.6 15.2s-6.6 8.6-11.9 9.6L391 391 371.1 498.9c-1 5.3-4.6 9.8-9.6 11.9s-10.7 1.5-15.2-1.6L256 446.9l-90.3 62.3c-4.5 3.1-10.2 3.7-15.2 1.6s-8.6-6.6-9.6-11.9L121 391 13.1 371.1c-5.3-1-9.8-4.6-11.9-9.6s-1.5-10.7 1.6-15.2L65.1 256 2.8 165.7c-3.1-4.5-3.7-10.2-1.6-15.2s6.6-8.6 11.9-9.6L121 121 140.9 13.1c1-5.3 4.6-9.8 9.6-11.9s10.7-1.5 15.2 1.6L256 65.1 346.3 2.8c4.5-3.1 10.2-3.7 15.2-1.6zM160 256a96 96 0 1 0 192 0 96 96 0 1 0-192 0z"
    },
    moon: {
      viewBox: "0 0 384 512",
      path: "M223.5 32C100 32 0 132.3 0 256s100 224 223.5 224c60.6 0 115.5-24.2 155.8-63.4c5-4.9 6.3-12.5 3.1-18.7s-10.1-9.7-17-8.5c-9.8 1.7-19.8 2.6-30.1 2.6c-96.9 0-175.5-78.8-175.5-176c0-65.8 36-123.1 89.3-153.3c6.1-3.5 9.2-10.5 7.7-17.3S249.8 33.8 242.9 33c-6.4-.7-12.9-1-19.4-1z"
    }
  }

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
    const icon = isDark ? this.constructor.icons.sun : this.constructor.icons.moon
    this.iconTarget.setAttribute("viewBox", icon.viewBox)
    this.iconTarget.innerHTML = `<path d="${icon.path}" />`

    if (isDark) {
      this.textTarget.textContent = "Activer Mode clair"
    } else {
      this.textTarget.textContent = "Activer Mode sombre"
    }
  }
}
