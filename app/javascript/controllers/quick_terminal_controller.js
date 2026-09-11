import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["output", "input", "spinner", "statusBadge"]
  static values = {
    url: String,
    promptPrefix: String
  }

  connect() {
    this.history = []
    this.historyIndex = -1
    this.currentDraft = ""
  }

  handleKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.submit()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.navigateHistory(-1)
    } else if (event.key === "ArrowDown") {
      event.preventDefault()
      this.navigateHistory(1)
    } else if (event.ctrlKey && event.key === "l") {
      event.preventDefault()
      this.clear()
    }
  }

  navigateHistory(direction) {
    if (this.history.length === 0) return

    if (this.historyIndex === -1 && direction === -1) {
      this.currentDraft = this.inputTarget.value
      this.historyIndex = this.history.length - 1
    } else if (this.historyIndex !== -1) {
      const newIndex = this.historyIndex + direction
      if (newIndex >= 0 && newIndex < this.history.length) {
        this.historyIndex = newIndex
      } else if (newIndex >= this.history.length) {
        this.historyIndex = -1
        this.inputTarget.value = this.currentDraft
        return
      } else {
        return
      }
    } else {
      return
    }

    if (this.historyIndex >= 0 && this.historyIndex < this.history.length) {
      this.inputTarget.value = this.history[this.historyIndex]
      // Move cursor to end
      setTimeout(() => {
        this.inputTarget.selectionStart = this.inputTarget.selectionEnd = this.inputTarget.value.length
      }, 0)
    }
  }

  submit() {
    const command = this.inputTarget.value.trim()
    if (!command) return

    this.history.push(command)
    this.historyIndex = -1
    this.currentDraft = ""
    this.inputTarget.value = ""

    this.processCommand(command)
  }

  runChip(event) {
    const command = event.currentTarget.dataset.command
    if (!command) return

    this.history.push(command)
    this.historyIndex = -1
    this.currentDraft = ""
    this.inputTarget.value = ""
    this.processCommand(command)
  }

  processCommand(command) {
    const trimmed = command.trim()

    if (trimmed === "clear") {
      this.clear()
      return
    }

    if (trimmed === "help") {
      this.renderCommandEcho(command)
      this.renderLocalHelp()
      this.scrollToBottom()
      return
    }

    this.executeRemoteCommand(command)
  }

  renderCommandEcho(command) {
    const entry = document.createElement("div")
    entry.className = "space-y-1 pt-2 border-t border-gray-800/80 first:border-0 first:pt-0"

    const header = document.createElement("div")
    header.className = "flex items-center justify-between gap-2 text-xs font-mono"

    const promptSpan = document.createElement("div")
    promptSpan.className = "flex items-center gap-2 flex-wrap min-w-0"
    promptSpan.innerHTML = `
      <span class="text-cyan-400 font-semibold select-none">${this.escapeHtml(this.promptPrefixValue)}</span>
      <span class="text-gray-100 font-medium break-all">${this.escapeHtml(command)}</span>
    `

    header.appendChild(promptSpan)
    entry.appendChild(header)
    this.outputTarget.appendChild(entry)
    this.scrollToBottom()
    return entry
  }

  async executeRemoteCommand(command) {
    const entry = this.renderCommandEcho(command)

    this.setRunning(true)

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken || ""
        },
        body: JSON.stringify({ command: command })
      })

      const data = await response.json()
      this.renderResult(entry, data)
    } catch (error) {
      this.renderResult(entry, {
        success: false,
        exit_code: 1,
        stdout: "",
        stderr: `Network or client error: ${error.message}`,
        duration: 0.0
      })
    } finally {
      this.setRunning(false)
      this.scrollToBottom()
      this.inputTarget.focus()
    }
  }

  renderResult(entry, data) {
    // Add duration & status badge to the entry header
    const header = entry.querySelector(".text-xs.font-mono")
    if (header) {
      const meta = document.createElement("div")
      meta.className = "flex items-center gap-2 shrink-0 text-[11px]"

      const durationText = data.duration !== undefined ? `${data.duration}s` : ""
      const isSuccess = data.success === true

      meta.innerHTML = `
        ${durationText ? `<span class="text-gray-500 font-mono">(${durationText})</span>` : ""}
        <span class="inline-flex items-center gap-1 font-semibold ${isSuccess ? "text-green-400" : "text-rose-400"}">
          <i class="fa-solid ${isSuccess ? "fa-circle-check" : "fa-circle-xmark"} h-3 w-3"></i>
          <span>${data.exit_code !== undefined ? `exit ${data.exit_code}` : isSuccess ? "ok" : "err"}</span>
        </span>
      `
      header.appendChild(meta)
    }

    // Append stdout
    if (data.stdout && data.stdout.trim().length > 0) {
      const preOut = document.createElement("pre")
      preOut.className = "whitespace-pre-wrap break-all text-gray-300 font-mono text-xs leading-5 select-text pl-2 border-l border-cyan-900/60"
      preOut.textContent = data.stdout
      entry.appendChild(preOut)
    }

    // Append stderr
    if (data.stderr && data.stderr.trim().length > 0) {
      const preErr = document.createElement("pre")
      preErr.className = "whitespace-pre-wrap break-all text-rose-400 font-mono text-xs leading-5 select-text pl-2 border-l border-rose-900/60"
      preErr.textContent = data.stderr
      entry.appendChild(preErr)
    }

    if ((!data.stdout || data.stdout.trim().length === 0) && (!data.stderr || data.stderr.trim().length === 0)) {
      const emptyNotice = document.createElement("p")
      emptyNotice.className = "text-gray-600 font-mono text-xs italic pl-2"
      emptyNotice.textContent = "(no output)"
      entry.appendChild(emptyNotice)
    }
  }

  renderLocalHelp() {
    const helpBox = document.createElement("div")
    helpBox.className = "rounded bg-gray-900/70 border border-gray-800 p-3 text-xs font-mono text-gray-300 space-y-2 mt-1"
    helpBox.innerHTML = `
      <p class="font-bold text-cyan-300">Sentinel Quick Terminal Help</p>
      <p class="text-gray-400">Commands are strictly executed inside the project root on the VPS.</p>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-2 text-[11px] pt-1">
        <div>
          <span class="text-gray-400 font-semibold block">Inspection & Files:</span>
          <span class="text-gray-300">cat, head, tail, grep, ls, find, wc, diff</span>
        </div>
        <div>
          <span class="text-gray-400 font-semibold block">System & Stats:</span>
          <span class="text-gray-300">uptime, df, free, ps, pwd, date, whoami</span>
        </div>
        <div>
          <span class="text-gray-400 font-semibold block">Docker & Git:</span>
          <span class="text-gray-300">docker compose ps, git status, git log</span>
        </div>
        <div>
          <span class="text-gray-400 font-semibold block">Project Scripts:</span>
          <span class="text-gray-300">./status.sh, ./deploy.sh, ./*.sh</span>
        </div>
      </div>
      <p class="text-gray-500 text-[11px] pt-1">
        Tips: Use <kbd class="px-1 py-0.5 bg-gray-800 rounded">↑</kbd> and <kbd class="px-1 py-0.5 bg-gray-800 rounded">↓</kbd> for history. Type <code class="text-cyan-400">clear</code> or press <kbd class="px-1 py-0.5 bg-gray-800 rounded">Ctrl+L</kbd> to reset.
      </p>
    `
    this.outputTarget.appendChild(helpBox)
  }

  clear() {
    this.outputTarget.innerHTML = ""
    this.inputTarget.focus()
  }

  setRunning(isRunning) {
    if (this.hasSpinnerTarget) {
      if (isRunning) {
        this.spinnerTarget.classList.remove("hidden")
      } else {
        this.spinnerTarget.classList.add("hidden")
      }
    }

    if (this.hasStatusBadgeTarget) {
      if (isRunning) {
        this.statusBadgeTarget.innerHTML = `
          <span class="h-2 w-2 rounded-full bg-cyan-400 animate-pulse"></span>
          <span class="text-cyan-300">Running...</span>
        `
      } else {
        this.statusBadgeTarget.innerHTML = `
          <span class="h-2 w-2 rounded-full bg-green-400"></span>
          <span class="text-gray-400">Ready</span>
        `
      }
    }

    this.inputTarget.disabled = isRunning
    if (!isRunning) {
      this.inputTarget.focus()
    }
  }

  scrollToBottom() {
    const container = this.outputTarget.parentElement
    if (container) {
      container.scrollTop = container.scrollHeight
    }
  }

  escapeHtml(str) {
    if (!str) return ""
    return str
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;")
  }
}
