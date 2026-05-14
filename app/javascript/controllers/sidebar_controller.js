import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sidebar", "header", "full", "navItem"]
  static values = { collapsed: Boolean }

  connect() {
    this.apply()
  }

  toggle() {
    this.collapsedValue = !this.collapsedValue
    this.apply()
  }

  apply() {
    this.sidebarTarget.classList.toggle("lg:w-18", this.collapsedValue)
    this.sidebarTarget.classList.toggle("lg:w-64", !this.collapsedValue)

    this.headerTarget.classList.toggle("lg:flex-col", this.collapsedValue)
    this.headerTarget.classList.toggle("lg:justify-start", this.collapsedValue)
    this.headerTarget.classList.toggle("lg:gap-3", this.collapsedValue)

    this.fullTargets.forEach((target) => {
      target.classList.toggle("lg:hidden", this.collapsedValue)
    })

    this.navItemTargets.forEach((target) => {
      target.classList.toggle("lg:justify-center", this.collapsedValue)
      target.classList.toggle("lg:gap-0", this.collapsedValue)
    })
  }
}
