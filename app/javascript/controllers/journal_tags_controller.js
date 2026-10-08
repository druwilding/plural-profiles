import { Controller } from "@hotwired/stimulus"

// Tag suggestions on the journal's Write page (docs/plan-journal.md, "Tag
// suggestions"). Works like the emote autocomplete (emote_input_controller),
// but on the tag being typed, the text between the commas around the caret,
// and from the first character. Up/Down move, Enter or Tab choose, Escape
// dismisses. Choosing puts the tag in, followed by ", " for the next one.
//
// The journal's tags arrive with the page as JSON (the "list" target), so
// suggestions come instantly. Without JavaScript it's a plain comma-separated
// field.

let nextId = 0

// Every tag containing what's typed, ignoring case and taking every
// character literally (some tags start with "*"): those starting with it
// first, then the rest, each in the list's own order. Tags already in the
// field aren't offered again.
function matchTags(tags, typed, used) {
  const query = typed.toLowerCase()
  const starting = []
  const containing = []
  for (const tag of tags) {
    const name = tag.toLowerCase()
    if (used.has(name)) continue
    if (name.startsWith(query)) starting.push(tag)
    else if (name.includes(query)) containing.push(tag)
  }
  return starting.concat(containing)
}

// The tag the caret is in: from just after the comma before it (and any
// spaces) to the comma after it, or the end.
function tagAtCaret(field) {
  const caret = field.selectionStart
  if (caret === null || caret !== field.selectionEnd) return null

  const value = field.value
  let start = value.lastIndexOf(",", caret - 1) + 1
  while (start < caret && value[start] === " ") start++
  const nextComma = value.indexOf(",", caret)
  const end = nextComma === -1 ? value.length : nextComma

  const typed = value.slice(start, caret)
  if (typed.trim() === "") return null
  return { start, end, typed }
}

// Every other tag in the field, lowercased.
function usedTags(field, token) {
  const others = field.value.slice(0, token.start) + field.value.slice(token.end)
  return new Set(others.split(",").map((tag) => tag.trim().toLowerCase()).filter(Boolean))
}

export default class extends Controller {
  static targets = [ "field", "list" ]

  connect() {
    this.id = ++nextId
    this.tags = JSON.parse(this.listTarget.textContent)
    this.isOpen = false
    this.matches = []
    this.token = null
    this.dismissed = null

    const field = this.fieldTarget
    field.setAttribute("role", "combobox")
    field.setAttribute("aria-autocomplete", "list")
    field.setAttribute("aria-expanded", "false")

    this.onKeydown = this.onKeydown.bind(this)
    this.onInput = this.onInput.bind(this)
    this.onCaretMove = this.onCaretMove.bind(this)
    this.onBlur = this.onBlur.bind(this)
    this.onBeforeCache = this.onBeforeCache.bind(this)

    field.addEventListener("keydown", this.onKeydown)
    field.addEventListener("input", this.onInput)
    field.addEventListener("compositionend", this.onInput)
    field.addEventListener("click", this.onCaretMove)
    field.addEventListener("keyup", this.onCaretMove)
    field.addEventListener("blur", this.onBlur)
    document.addEventListener("turbo:before-cache", this.onBeforeCache)
  }

  disconnect() {
    const field = this.fieldTarget
    field.removeEventListener("keydown", this.onKeydown)
    field.removeEventListener("input", this.onInput)
    field.removeEventListener("compositionend", this.onInput)
    field.removeEventListener("click", this.onCaretMove)
    field.removeEventListener("keyup", this.onCaretMove)
    field.removeEventListener("blur", this.onBlur)
    document.removeEventListener("turbo:before-cache", this.onBeforeCache)
    this.closeMenu()
  }

  // Text still being composed with an IME isn't final; compositionend
  // updates once it is.
  onInput(event) {
    if (event.isComposing || this.choosing) return
    this.update({ fromInput: true })
  }

  onCaretMove(event) {
    if (event.type === "keyup" && ![ "ArrowLeft", "ArrowRight", "Home", "End" ].includes(event.key)) return
    this.update()
  }

  onBlur() {
    this.closeMenu()
  }

  onBeforeCache() {
    this.closeMenu()
  }

  onKeydown(event) {
    if (!this.isOpen || event.isComposing) return

    const count = this.matches.length
    switch (event.key) {
      case "ArrowDown":
        this.highlight((this.activeIndex + 1) % count)
        break
      case "ArrowUp":
        this.highlight((this.activeIndex - 1 + count) % count)
        break
      case "Enter":
      case "Tab":
        // Shift+Tab still moves focus back.
        if (event.shiftKey || event.altKey || event.ctrlKey || event.metaKey) return
        this.choose(this.activeIndex)
        break
      case "Escape":
        // Stays closed until what's typed changes.
        this.dismissed = this.tokenKey(this.token)
        this.closeMenu()
        break
      default:
        return
    }
    event.preventDefault()
  }

  // fromInput: the text changed, rather than just the caret moving. Only that
  // lifts an Escape dismissal.
  update({ fromInput = false } = {}) {
    const token = tagAtCaret(this.fieldTarget)
    if (fromInput) this.dismissed = null
    if (!token || this.tokenKey(token) === this.dismissed) {
      this.closeMenu()
      return
    }

    const matches = matchTags(this.tags, token.typed, usedTags(this.fieldTarget, token))
    if (matches.length === 0) {
      this.closeMenu()
      return
    }

    const unchanged = this.isOpen && this.tokenKey(this.token) === this.tokenKey(token)
    this.token = token
    this.openMenu()
    if (!unchanged) {
      this.matches = matches
      this.renderMenu()
    }
  }

  tokenKey(token) {
    return token ? `${token.start}:${token.typed}` : null
  }

  get menu() {
    if (!this.menuElement) {
      const menu = document.createElement("ul")
      menu.id = `journal-tags-menu-${this.id}`
      menu.className = "journal-tags__menu"
      menu.setAttribute("role", "listbox")
      menu.setAttribute("aria-label", "Matching tags")
      menu.hidden = true
      // Keep focus (and the caret) in the field when an option is clicked.
      menu.addEventListener("mousedown", (event) => event.preventDefault())
      menu.addEventListener("click", (event) => {
        const option = event.target.closest("[role='option']")
        if (option) this.choose(Number(option.dataset.index))
      })

      const status = document.createElement("div")
      status.className = "visually-hidden"
      status.setAttribute("aria-live", "polite")

      this.element.append(menu, status)
      this.fieldTarget.setAttribute("aria-controls", menu.id)
      this.menuElement = menu
      this.statusElement = status
    }
    return this.menuElement
  }

  renderMenu() {
    const options = this.matches.map((tag, index) => {
      const option = document.createElement("li")
      option.id = `${this.menu.id}-option-${index}`
      option.className = "journal-tags__option"
      option.setAttribute("role", "option")
      option.dataset.index = index
      option.textContent = tag
      return option
    })
    this.menu.replaceChildren(...options)
    this.menu.scrollTop = 0
    this.highlight(0, { announceCount: true })
  }

  highlight(index, { announceCount = false } = {}) {
    this.activeIndex = index
    const menu = this.menu
    menu.querySelectorAll("[role='option']").forEach((option, optionIndex) => {
      const active = optionIndex === index
      option.setAttribute("aria-selected", active ? "true" : "false")
      option.classList.toggle("journal-tags__option--active", active)
      if (!active) return

      this.fieldTarget.setAttribute("aria-activedescendant", option.id)
      // Scroll just the menu; scrollIntoView would also scroll the page.
      if (option.offsetTop < menu.scrollTop) {
        menu.scrollTop = option.offsetTop
      } else if (option.offsetTop + option.offsetHeight > menu.scrollTop + menu.clientHeight) {
        menu.scrollTop = option.offsetTop + option.offsetHeight - menu.clientHeight
      }
    })

    const tag = this.matches[index]
    const count = this.matches.length
    this.statusElement.textContent = announceCount
      ? `${count} ${count === 1 ? "tag" : "tags"} found, ${tag} selected`
      : tag
  }

  openMenu() {
    this.menu.hidden = false
    this.fieldTarget.setAttribute("aria-expanded", "true")
    this.isOpen = true
  }

  closeMenu() {
    if (!this.isOpen) return
    this.isOpen = false
    this.token = null
    this.menu.hidden = true
    this.statusElement.textContent = ""
    this.fieldTarget.setAttribute("aria-expanded", "false")
    this.fieldTarget.removeAttribute("aria-activedescendant")
  }

  // Replaces the tag being typed with the chosen one. At the end of the
  // field, ", " follows, ready for the next tag; in the middle, the caret
  // moves past the comma already there.
  choose(index) {
    const tag = this.matches[index]
    const { start, end } = this.token
    const field = this.fieldTarget
    const atEnd = field.value.slice(end).trim() === ""
    const text = atEnd ? `${tag}, ` : tag
    this.closeMenu()

    field.focus()
    field.setSelectionRange(start, atEnd ? field.value.length : end)
    // The insert fires an input event of its own, which mustn't reopen the
    // list on the tag just chosen.
    this.choosing = true
    // execCommand keeps the browser's own undo history (so Ctrl+Z undoes
    // it); setRangeText is the fallback where it isn't supported.
    let inserted = false
    try {
      inserted = document.execCommand("insertText", false, text)
    } catch {
      inserted = false
    }
    if (!inserted) {
      field.setRangeText(text, start, atEnd ? field.value.length : end, "end")
      field.dispatchEvent(new Event("input", { bubbles: true }))
    }
    this.choosing = false

    if (!atEnd) {
      const after = field.value.slice(start + text.length).match(/^,\s*/)
      const caret = start + text.length + (after ? after[0].length : 0)
      field.setSelectionRange(caret, caret)
    }
  }
}
