import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "searchInput",
    "clearButton",
    "searchCount",
    "searchResultsBanner",
    "emptyState",
    "emptyQueryText",
    "tabButton",
    "tabPanel",
    "faqDetails",
    "mobileSelect"
  ]

  static values = {
    activeTab: { type: String, default: "overview" }
  }

  connect() {
    this.boundKeyHandler = this.handleKeydown.bind(this)
    window.addEventListener("keydown", this.boundKeyHandler)

    // Check initial hash in URL
    const hash = window.location.hash ? window.location.hash.substring(1) : ""
    if (hash && this.isValidTab(hash)) {
      this.activeTabValue = hash
    } else {
      this.activeTabValue = "overview"
    }

    this.renderTabs()
  }

  disconnect() {
    if (this.boundKeyHandler) {
      window.removeEventListener("keydown", this.boundKeyHandler)
    }
  }

  handleKeydown(event) {
    const activeEl = document.activeElement
    const isEditing = activeEl && (
      activeEl.tagName === "INPUT" ||
      activeEl.tagName === "TEXTAREA" ||
      activeEl.isContentEditable
    )

    if ((event.key === "/" && !isEditing) || ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k")) {
      event.preventDefault()
      if (this.hasSearchInputTarget) {
        this.searchInputTarget.focus()
        this.searchInputTarget.select()
      }
    } else if (event.key === "Escape" && this.hasSearchInputTarget && document.activeElement === this.searchInputTarget) {
      this.clearSearch()
      this.searchInputTarget.blur()
    }
  }

  switchTab(event) {
    event.preventDefault()
    const tabId = event.currentTarget.dataset.tabId
    if (!tabId) return

    if (this.hasSearchInputTarget && this.searchInputTarget.value.trim().length > 0) {
      this.searchInputTarget.value = ""
      this.search()
    }

    this.selectTab(tabId)
  }

  onMobileSelect(event) {
    const tabId = event.target.value
    if (tabId) {
      if (this.hasSearchInputTarget && this.searchInputTarget.value.trim().length > 0) {
        this.searchInputTarget.value = ""
        this.search()
      }
      this.selectTab(tabId)
    }
  }

  quickJump(event) {
    event.preventDefault()
    const tabId = event.currentTarget.dataset.tabId
    if (tabId) {
      this.selectTab(tabId)
    }
  }

  selectTab(tabId) {
    this.activeTabValue = tabId
    this.renderTabs()

    if (tabId !== "overview" && tabId !== "all") {
      if (history.pushState) {
        history.pushState(null, null, `#${tabId}`)
      } else {
        window.location.hash = `#${tabId}`
      }
    } else {
      if (history.pushState) {
        history.pushState(null, null, " ")
      }
    }

    const contentAnchor = document.getElementById("docs-content-area")
    if (contentAnchor) {
      contentAnchor.scrollIntoView({ behavior: "smooth", block: "start" })
    }
  }

  renderTabs() {
    const current = this.activeTabValue

    // Update Tab Buttons
    this.tabButtonTargets.forEach((btn) => {
      const isSelected = btn.dataset.tabId === current
      btn.setAttribute("aria-selected", isSelected ? "true" : "false")

      if (isSelected) {
        btn.className = "flex items-center gap-2 whitespace-nowrap rounded-lg bg-cyan-600 px-3.5 py-2 text-xs font-semibold text-white shadow-sm transition-all dark:bg-cyan-500 dark:text-gray-950 ring-1 ring-cyan-500"
      } else {
        btn.className = "flex items-center gap-2 whitespace-nowrap rounded-lg bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-800 px-3.5 py-2 text-xs font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-800/80 hover:text-gray-900 dark:hover:text-white transition-all shadow-xs"
      }
    })

    // Update Mobile Select
    if (this.hasMobileSelectTarget) {
      this.mobileSelectTarget.value = current
    }

    // Show/Hide Panels
    this.tabPanelTargets.forEach((panel) => {
      const panelId = panel.dataset.panelId
      if (current === "all") {
        panel.classList.remove("hidden")
      } else if (current === "overview") {
        panel.classList.toggle("hidden", panelId !== "overview")
      } else {
        panel.classList.toggle("hidden", panelId !== current)
      }
    })

    // Hide search results banner and empty state
    if (this.hasSearchResultsBannerTarget) {
      this.searchResultsBannerTarget.classList.add("hidden")
    }
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.add("hidden")
    }
  }

  search() {
    const rawQuery = this.hasSearchInputTarget ? this.searchInputTarget.value : ""
    const query = this.normalize(rawQuery.trim())

    if (this.hasClearButtonTarget) {
      this.clearButtonTarget.classList.toggle("hidden", query.length === 0)
    }

    if (query.length === 0) {
      this.renderTabs()
      return
    }

    let matchCount = 0

    this.tabPanelTargets.forEach((panel) => {
      const panelId = panel.dataset.panelId
      if (panelId === "overview") {
        panel.classList.add("hidden")
        return
      }

      const panelText = this.normalize(panel.textContent || "")
      const keywords = this.normalize(panel.dataset.docKeywords || "")
      const isMatch = `${keywords} ${panelText}`.includes(query)

      panel.classList.toggle("hidden", !isMatch)

      if (isMatch) {
        matchCount++

        const detailsList = panel.querySelectorAll("details")
        detailsList.forEach((detail) => {
          const detailText = this.normalize(detail.textContent || "")
          if (detailText.includes(query)) {
            detail.open = true
          }
        })
      }
    })

    if (this.hasSearchResultsBannerTarget) {
      this.searchResultsBannerTarget.classList.remove("hidden")
    }
    if (this.hasSearchCountTarget) {
      const plural = matchCount > 1 ? "guides trouvés" : "guide trouvé"
      this.searchCountTarget.textContent = `${matchCount} ${plural}`
    }

    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.toggle("hidden", matchCount > 0)
      if (this.hasEmptyQueryTextTarget) {
        this.emptyQueryTextTarget.textContent = rawQuery
      }
    }
  }

  clearSearch(event) {
    if (event) event.preventDefault()
    if (this.hasSearchInputTarget) {
      this.searchInputTarget.value = ""
    }
    this.search()
    if (this.hasSearchInputTarget) {
      this.searchInputTarget.focus()
    }
  }

  filterTag(event) {
    event.preventDefault()
    const query = event.currentTarget.dataset.tag || ""
    if (this.hasSearchInputTarget) {
      this.searchInputTarget.value = query
      this.search()
      this.searchInputTarget.focus()
    }
  }

  copySnippet(event) {
    event.preventDefault()
    const button = event.currentTarget
    const container = button.closest(".code-block-container")
    const codeElement = container?.querySelector("code")
    const textToCopy = button.dataset.copyText || codeElement?.innerText || ""

    if (!textToCopy) return

    navigator.clipboard.writeText(textToCopy).then(() => {
      const originalHtml = button.innerHTML
      button.innerHTML = `
        <span class="inline-flex items-center gap-1.5 text-emerald-600 dark:text-emerald-400 font-semibold text-xs">
          <svg class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
          </svg>
          Copié !
        </span>
      `
      button.setAttribute("disabled", "true")

      setTimeout(() => {
        button.innerHTML = originalHtml
        button.removeAttribute("disabled")
      }, 2000)
    }).catch((err) => {
      console.warn("Clipboard copy failed:", err)
    })
  }

  copyLink(event) {
    event.preventDefault()
    const sectionId = event.currentTarget.dataset.sectionId
    if (!sectionId) return

    const url = `${window.location.origin}${window.location.pathname}#${sectionId}`
    navigator.clipboard.writeText(url).then(() => {
      const button = event.currentTarget
      const originalTitle = button.getAttribute("title")
      button.setAttribute("title", "Lien copié !")

      const feedback = button.querySelector(".link-copied-feedback")
      if (feedback) {
        feedback.classList.remove("hidden")
        setTimeout(() => {
          feedback.classList.add("hidden")
          if (originalTitle) button.setAttribute("title", originalTitle)
        }, 1800)
      }
    })
  }

  expandAllFaq(event) {
    if (event) event.preventDefault()
    this.faqDetailsTargets.forEach((details) => {
      details.open = true
    })
  }

  collapseAllFaq(event) {
    if (event) event.preventDefault()
    this.faqDetailsTargets.forEach((details) => {
      details.open = false
    })
  }

  isValidTab(id) {
    const valid = [
      "overview",
      "onboarding",
      "cron-contract",
      "maintenance",
      "observability",
      "quick-terminal",
      "umami",
      "authentik",
      "ops-center",
      "faq",
      "all"
    ]
    return valid.includes(id)
  }

  normalize(str) {
    return str
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
  }
}
