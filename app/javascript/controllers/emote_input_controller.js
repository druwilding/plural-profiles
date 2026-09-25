import { Controller } from "@hotwired/stimulus"

// Emote entry for any field that renders emote codes. The field is wrapped by
// ApplicationHelper#emote_field, which also renders the (hidden until
// connected) emote button. Two ways in, both inserting the canonical code
// (`:spring-heart:`) plus a trailing space, so what's saved is always the
// plain code:
//
//  - The emote button opens a dialog of every emote. One dialog is shared by
//    every field on the page; it's built on first use and appended to
//    <body>, so it sits outside any <form> and can never submit one.
//  - Typing `:` or `;` and at least two characters opens an autocomplete menu
//    at the caret, with the best matches first (see matchEmotes). Up/Down
//    move the highlight, Enter/Tab insert, Escape dismisses.
//
// The emote list itself comes from ApplicationHelper#emote_list_json_tag.

const MIN_QUERY_LENGTH = 2

// An open emote code right before the caret: a delimiter and the name typed
// so far. What comes before the delimiter is checked separately in
// openCodeAtCaret — a letter or number there means it's not an emote code at
// all (10:30, https://ab, note:ab).
const OPEN_CODE = /[:;]([\p{L}\p{N}_-]+)$/u
const COMPLETE_CODE = /[:;]([a-z0-9_-]+)[:;]$/i

// A number before the name in an old Discord-numbered code, e.g. the "11-" in
// "11-aqua-heart". Only stripped when a letter follows, so "100" stays "100".
// Mirrors EmoteRegistry::LEGACY_NUMBER_PREFIX.
const LEGACY_NUMBER_PREFIX = /^\d+-?(?=[a-z])/
const WORD_CHARACTER = /[\p{L}\p{N}_]/u

const CARET_KEYS = [ "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End", "PageUp", "PageDown" ]

// Everything that affects where text wraps, copied onto the mirror element
// caretCoordinates uses to find the caret's position.
const MIRRORED_PROPERTIES = [
  "boxSizing", "width", "borderTopWidth", "borderRightWidth", "borderBottomWidth", "borderLeftWidth", "borderStyle",
  "paddingTop", "paddingRight", "paddingBottom", "paddingLeft",
  "fontStyle", "fontVariant", "fontWeight", "fontStretch", "fontSize", "fontFamily", "lineHeight",
  "textAlign", "textTransform", "textIndent", "letterSpacing", "wordSpacing", "tabSize"
]

let emoteList = null
let emoteSource = null
let sharedDialog = null
let nextId = 0

// Parsed again whenever the JSON element changes: it's in the body, which
// Turbo replaces on every visit, so the list stays current when emotes change
// (e.g. after an admin uploads some) without a full page load.
function emotes() {
  const source = document.getElementById("emote-list")
  if (source !== emoteSource) {
    emoteSource = source
    emoteList = source ? JSON.parse(source.textContent) : []
  }
  return emoteList
}

// "spring-heart" from ":spring-heart:"
function codeOf(emote) {
  return emote.code.slice(1, -1)
}

// Same normalisation as EmoteRegistry#resolve: case-insensitive, and
// underscores (or spaces, from the dialog search) for hyphens.
function normaliseQuery(query) {
  return query.trim().toLowerCase().replace(/[\s_]+/g, "-")
}

// Matches in tiers, each in display order:
// 1. an exact name or code (":100" puts 100 first)
// 2. codes starting with the query ("abyss-he" finds abyss, ":10" finds 100)
// 3. names starting with it (":02" finds 02-spring-heart, ":10" 10-aqua-heart)
// 4. codes containing it anywhere, without the "-heart" suffix so "he"
//    doesn't match every single heart
// An old Discord number prefix ("11-aq") also matches by what follows it.
function matchEmotes(query) {
  const typed = normaliseQuery(query)
  if (!typed) return []
  const bare = typed.replace(LEGACY_NUMBER_PREFIX, "")

  const tiers = [ [], [], [], [] ]
  for (const emote of emotes()) {
    const code = codeOf(emote)
    if (emote.name === typed || code === typed) tiers[0].push(emote)
    else if (code.startsWith(typed) || code.startsWith(bare)) tiers[1].push(emote)
    else if (emote.name.startsWith(typed)) tiers[2].push(emote)
    else if (code.replace(/-heart$/, "").includes(bare)) tiers[3].push(emote)
  }
  return tiers.flat()
}

// Whether a finished code (without its delimiters) is an emote, by the same
// rules as EmoteRegistry#resolve apart from old codes (aliases).
function isEmoteCode(value) {
  const typed = normaliseQuery(value)
  const bare = typed.replace(LEGACY_NUMBER_PREFIX, "")
  return emotes().some((emote) => emote.name === typed || codeOf(emote) === typed || codeOf(emote) === bare)
}

function openCodeAtCaret(field) {
  const caret = field.selectionStart
  if (caret === null || caret !== field.selectionEnd) return null

  const before = field.value.slice(0, caret)
  const match = before.match(OPEN_CODE)
  if (!match) return null

  const start = caret - match[0].length
  const preceding = before.slice(0, start)
  const characterBefore = preceding.slice(-1)
  if (characterBefore === ":" || characterBefore === ";") {
    // Only straight after a finished emote code (:red-heart::ab), so emotes
    // can sit side by side — not after a stray delimiter (::ab).
    const complete = preceding.match(COMPLETE_CODE)
    if (!complete || !isEmoteCode(complete[1])) return null
  } else if (WORD_CHARACTER.test(characterBefore)) {
    return null
  }

  const query = normaliseQuery(match[1])
  if (query.length < MIN_QUERY_LENGTH) return null

  return { start, end: caret, query, text: match[0] }
}

// Where the character at `position` sits inside the field, relative to the
// field's border box. Textareas and inputs don't expose this, so lay the same
// text out in an invisible element with identical wrapping and measure a
// marker placed at that position.
function caretCoordinates(field, position) {
  const style = getComputedStyle(field)
  const singleLine = field.tagName === "INPUT"
  const mirror = document.createElement("div")
  for (const property of MIRRORED_PROPERTIES) mirror.style[property] = style[property]
  Object.assign(mirror.style, {
    position: "absolute",
    visibility: "hidden",
    top: "0",
    left: "-9999px",
    overflow: "hidden",
    whiteSpace: singleLine ? "pre" : "pre-wrap",
    overflowWrap: singleLine ? "normal" : "break-word"
  })
  mirror.textContent = field.value.slice(0, position)
  const marker = document.createElement("span")
  marker.textContent = field.value.slice(position) || "."
  mirror.append(marker)
  document.body.append(mirror)

  const coordinates = {
    top: marker.offsetTop + parseFloat(style.borderTopWidth) - field.scrollTop,
    left: marker.offsetLeft + parseFloat(style.borderLeftWidth) - field.scrollLeft,
    height: parseFloat(style.lineHeight) || parseFloat(style.fontSize) * 1.2
  }
  mirror.remove()
  return coordinates
}

export default class extends Controller {
  static targets = [ "field", "button" ]
  static values = { placement: { type: String, default: "below" } }

  connect() {
    this.id = ++nextId
    this.isOpen = false
    this.matches = []
    this.token = null
    this.dismissedToken = null
    // Before the field has ever been focused its selection is meaningless
    // (usually 0), so a picker insert then goes at the end instead.
    this.fieldFocused = document.activeElement === this.fieldTarget

    this.onKeydown = this.onKeydown.bind(this)
    this.onInput = this.onInput.bind(this)
    this.onCompositionEnd = this.onCompositionEnd.bind(this)
    this.onCaretMove = this.onCaretMove.bind(this)
    this.onFocus = this.onFocus.bind(this)
    this.onBlur = this.onBlur.bind(this)
    this.onBeforeCache = this.onBeforeCache.bind(this)

    // Capture phase on the wrapper runs before any keydown listener on the
    // field itself (e.g. composer#submitOnEnter), however those were wired
    // up, so an open menu always gets first claim on Enter.
    this.element.addEventListener("keydown", this.onKeydown, true)
    this.fieldTarget.addEventListener("input", this.onInput)
    this.fieldTarget.addEventListener("compositionend", this.onCompositionEnd)
    this.fieldTarget.addEventListener("click", this.onCaretMove)
    this.fieldTarget.addEventListener("keyup", this.onCaretMove)
    this.fieldTarget.addEventListener("focus", this.onFocus)
    this.fieldTarget.addEventListener("blur", this.onBlur)
    document.addEventListener("turbo:before-cache", this.onBeforeCache)

    this.fieldTarget.setAttribute("aria-autocomplete", "list")
    this.fieldTarget.setAttribute("aria-expanded", "false")
    if (this.hasButtonTarget) this.buttonTarget.hidden = false
  }

  disconnect() {
    this.element.removeEventListener("keydown", this.onKeydown, true)
    this.fieldTarget.removeEventListener("input", this.onInput)
    this.fieldTarget.removeEventListener("compositionend", this.onCompositionEnd)
    this.fieldTarget.removeEventListener("click", this.onCaretMove)
    this.fieldTarget.removeEventListener("keyup", this.onCaretMove)
    this.fieldTarget.removeEventListener("focus", this.onFocus)
    this.fieldTarget.removeEventListener("blur", this.onBlur)
    document.removeEventListener("turbo:before-cache", this.onBeforeCache)
    this.closeMenu()
  }

  // -- Picker dialog --

  openPicker() {
    const field = this.fieldTarget
    const end = field.value.length
    this.pickerSelection = this.fieldFocused
      ? { start: field.selectionStart ?? end, end: field.selectionEnd ?? end }
      : { start: end, end }
    emoteDialog().open(this)
  }

  insertFromPicker(emote) {
    const { start, end } = this.pickerSelection
    this.insert(emote, start, end)
  }

  restoreFocus() {
    const { start, end } = this.pickerSelection
    this.fieldTarget.focus()
    this.fieldTarget.setSelectionRange(start, end)
  }

  // -- Autocomplete menu --

  // Text still being composed with an IME isn't final, so wait for
  // compositionend — which, unlike the input events during composition,
  // isn't followed by another input event to update from.
  onInput(event) {
    if (event.isComposing) return
    this.update({ fromInput: true })
  }

  onCompositionEnd() {
    this.update({ fromInput: true })
  }

  onCaretMove(event) {
    if (event.type === "keyup" && !CARET_KEYS.includes(event.key)) return
    this.update()
  }

  onFocus() {
    this.fieldFocused = true
  }

  onBlur() {
    this.closeMenu()
  }

  onBeforeCache() {
    this.closeMenu()
    sharedDialog?.destroy()
  }

  onKeydown(event) {
    if (!this.isOpen || event.target !== this.fieldTarget || event.isComposing) return

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
        // Shift+Enter still makes a new line; Shift+Tab still moves focus.
        if (event.shiftKey || event.altKey || event.ctrlKey || event.metaKey) return
        this.choose(this.activeIndex)
        break
      case "Escape":
        // Stays dismissed until what's typed changes, rather than popping
        // straight back open on the next caret move.
        this.dismissedToken = this.tokenKey(this.token)
        this.closeMenu()
        break
      default:
        return
    }
    event.preventDefault()
  }

  // fromInput: the text changed, rather than just the caret moving. Only that
  // lifts an Escape dismissal — moving the caret off a dismissed code and back
  // shouldn't pop the menu open again.
  update({ fromInput = false } = {}) {
    const token = openCodeAtCaret(this.fieldTarget)
    if (!token) {
      if (fromInput) this.dismissedToken = null
      this.closeMenu()
      return
    }
    if (this.tokenKey(token) === this.dismissedToken) {
      this.closeMenu()
      return
    }
    if (fromInput) this.dismissedToken = null

    const matches = matchEmotes(token.query)
    if (matches.length === 0) {
      this.closeMenu()
      return
    }

    const unchanged = this.isOpen && this.token?.start === token.start && this.token?.query === token.query
    this.token = token
    this.openMenu()
    if (!unchanged) {
      this.matches = matches
      this.renderMenu()
    }
    this.positionMenu()
  }

  tokenKey(token) {
    return token ? `${token.start}:${token.text}` : null
  }

  get menu() {
    if (!this.menuElement) {
      const menu = document.createElement("ul")
      menu.id = `emote-input-menu-${this.id}`
      menu.className = "emote-input__menu"
      menu.setAttribute("role", "listbox")
      menu.setAttribute("aria-label", "Matching emotes")
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
    const options = this.matches.map((emote, index) => {
      const option = document.createElement("li")
      option.id = `${this.menu.id}-option-${index}`
      option.className = "emote-input__option"
      option.setAttribute("role", "option")
      option.dataset.index = index

      const image = document.createElement("img")
      image.src = emote.src
      image.alt = ""
      image.width = 24
      image.height = 24

      const label = document.createElement("span")
      label.textContent = emote.label

      option.append(image, label)
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
      option.classList.toggle("emote-input__option--active", active)
      if (!active) return

      this.fieldTarget.setAttribute("aria-activedescendant", option.id)
      // Scroll just the menu — scrollIntoView would also scroll the page.
      if (option.offsetTop < menu.scrollTop) {
        menu.scrollTop = option.offsetTop
      } else if (option.offsetTop + option.offsetHeight > menu.scrollTop + menu.clientHeight) {
        menu.scrollTop = option.offsetTop + option.offsetHeight - menu.clientHeight
      }
    })

    const label = this.matches[index].label
    const count = this.matches.length
    this.statusElement.textContent = announceCount
      ? `${count} ${count === 1 ? "emote" : "emotes"} found, ${label} selected`
      : label
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

  // Next to the typed code: below its line on normal forms, above it where the
  // field is pinned to the bottom of the screen (the chat composer). Kept
  // within the wrapper's width, so it never runs off a narrow screen.
  positionMenu() {
    const field = this.fieldTarget
    const menu = this.menu
    const caret = caretCoordinates(field, this.token.start)
    const fieldTop = field.offsetTop
    const lineTop = Math.max(fieldTop, fieldTop + caret.top)

    const maxLeft = Math.max(0, this.element.clientWidth - menu.offsetWidth)
    menu.style.left = `${Math.min(Math.max(0, field.offsetLeft + caret.left), maxLeft)}px`

    if (this.placementValue === "above") {
      menu.style.top = "auto"
      menu.style.bottom = `${this.element.clientHeight - lineTop + 4}px`
    } else {
      const lineBottom = Math.min(lineTop + caret.height, fieldTop + field.offsetHeight)
      menu.style.bottom = "auto"
      menu.style.top = `${lineBottom + 4}px`
    }
  }

  choose(index) {
    const emote = this.matches[index]
    const { start, end } = this.token
    this.closeMenu()
    this.insert(emote, start, end)
  }

  // -- Shared --

  insert(emote, start, end) {
    const field = this.fieldTarget
    const text = /\s/.test(field.value.charAt(end)) ? emote.code : `${emote.code} `

    field.focus()
    field.setSelectionRange(start, end)
    // execCommand keeps the browser's own undo history (so Ctrl+Z undoes the
    // insert) and fires a real input event, which the composer's auto-grow
    // and the chat identity preview listen for. setRangeText is the fallback
    // wherever execCommand isn't supported.
    let inserted = false
    try {
      inserted = document.execCommand("insertText", false, text)
    } catch {
      inserted = false
    }
    if (!inserted) {
      field.setRangeText(text, start, end, "end")
      field.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }
}

// [[group name, [emote, …]], …] in the order the emotes arrive, which is
// already group order then name order.
function groupEmotes(list) {
  const groups = new Map()
  for (const emote of list) {
    const group = emote.group || "Emotes"
    if (!groups.has(group)) groups.set(group, [])
    groups.get(group).push(emote)
  }
  return [ ...groups ]
}

// The button in the nearest row above (direction -1) or below (1) whose centre
// is closest horizontally to the current one's.
function nearestInRow(buttons, current, direction) {
  const from = current.getBoundingClientRect()
  const fromCentre = from.left + from.width / 2
  let rowTop = null
  let best = null
  let bestDistance = Infinity

  for (const button of buttons) {
    const rect = button.getBoundingClientRect()
    const below = rect.top > from.top + 1
    const above = rect.top < from.top - 1
    if ((direction > 0 && !below) || (direction < 0 && !above)) continue

    const closerRow = rowTop === null || (direction > 0 ? rect.top < rowTop - 1 : rect.top > rowTop + 1)
    const sameRow = rowTop !== null && Math.abs(rect.top - rowTop) <= 1
    if (!closerRow && !sameRow) continue
    if (closerRow) {
      rowTop = rect.top
      best = null
      bestDistance = Infinity
    }

    const distance = Math.abs(rect.left + rect.width / 2 - fromCentre)
    if (distance < bestDistance) {
      best = button
      bestDistance = distance
    }
  }
  return best
}

function emoteDialog() {
  if (sharedDialog && sharedDialog.emoteList !== emotes()) sharedDialog.destroy()
  if (!sharedDialog || !sharedDialog.element.isConnected) sharedDialog = new EmoteDialog()
  return sharedDialog
}

class EmoteDialog {
  constructor() {
    const dialog = document.createElement("dialog")
    dialog.className = "emote-dialog"
    dialog.setAttribute("aria-labelledby", "emote-dialog-title")
    dialog.innerHTML = `
      <div class="emote-dialog__header">
        <h2 class="emote-dialog__title" id="emote-dialog-title">Choose an emote</h2>
        <button type="button" class="emote-dialog__close" aria-label="Close">×</button>
      </div>
      <label class="visually-hidden" for="emote-dialog-search">Search emotes</label>
      <input type="search" id="emote-dialog-search" class="emote-dialog__search" placeholder="Search emotes…" autocomplete="off" spellcheck="false">
      <div class="emote-dialog__grid"></div>
      <p class="emote-dialog__empty" hidden>No emotes match that search.</p>
    `

    this.element = dialog
    this.search = dialog.querySelector(".emote-dialog__search")
    this.grid = dialog.querySelector(".emote-dialog__grid")
    this.empty = dialog.querySelector(".emote-dialog__empty")
    this.emoteList = emotes()
    this.buttons = new Map(this.emoteList.map((emote) => [ emote.name, this.buildButton(emote) ]))

    dialog.querySelector(".emote-dialog__close").addEventListener("click", () => dialog.close())
    dialog.addEventListener("click", (event) => this.onDialogClick(event))
    dialog.addEventListener("close", () => this.onClose())
    this.search.addEventListener("input", () => this.filter())
    this.search.addEventListener("keydown", (event) => this.onSearchKeydown(event))
    this.grid.addEventListener("click", (event) => {
      const button = event.target.closest(".emote-dialog__emote")
      if (button) this.choose(button.dataset.emote)
    })
    this.grid.addEventListener("keydown", (event) => this.onGridKeydown(event))

    document.body.append(dialog)
  }

  buildButton(emote) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "emote-dialog__emote"
    button.dataset.emote = emote.name
    button.title = emote.label
    button.setAttribute("aria-label", emote.label)

    const image = document.createElement("img")
    image.src = emote.src
    image.alt = ""
    image.width = 32
    image.height = 32
    image.loading = "lazy"

    const name = document.createElement("span")
    name.className = "emote-dialog__emote-name"
    name.textContent = emote.label

    button.append(image, name)
    return button
  }

  open(controller) {
    if (this.element.open) return
    this.controller = controller
    this.search.value = ""
    this.filter()
    this.element.showModal()
    this.search.focus()
  }

  // Removed entirely (open or not) before Turbo snapshots the page. Left in,
  // it would be restored from the cache as a lifeless copy with the same ids,
  // alongside the fresh dialog emoteDialog() then builds.
  destroy() {
    this.controller = null
    if (this.element.open) this.element.close()
    this.element.remove()
    if (sharedDialog === this) sharedDialog = null
  }

  // Browsing shows every emote in a section per group, in group order. A
  // search shows one list of matches, best first, so Enter picks the best.
  filter() {
    const query = this.search.value
    const sections = query.trim()
      ? [ this.buildSection(null, matchEmotes(query)) ]
      : groupEmotes(emotes()).map(([ group, members ]) => this.buildSection(group, members))
    this.grid.replaceChildren(...sections.filter(Boolean))

    const buttons = this.allButtons()
    this.empty.hidden = buttons.length > 0
    this.setTabStop(buttons[0])
  }

  buildSection(group, members) {
    if (members.length === 0) return null

    const section = document.createElement("section")
    section.className = "emote-dialog__group"
    const grid = document.createElement("div")
    grid.className = "emote-dialog__group-grid"
    grid.setAttribute("role", "group")

    if (group) {
      const heading = document.createElement("h3")
      heading.className = "emote-dialog__group-title"
      heading.id = `emote-dialog-group-${this.sectionCount = (this.sectionCount || 0) + 1}`
      heading.textContent = group
      grid.setAttribute("aria-labelledby", heading.id)
      section.append(heading)
    } else {
      grid.setAttribute("aria-label", "Matching emotes")
    }

    grid.append(...members.map((emote) => this.buttons.get(emote.name)))
    section.append(grid)
    return section
  }

  allButtons() {
    return [ ...this.grid.querySelectorAll(".emote-dialog__emote") ]
  }

  // Only one emote is in the tab order at a time; arrow keys move between
  // them (onGridKeydown), so Tab goes straight from the grid to what's next.
  setTabStop(target) {
    for (const button of this.allButtons()) button.tabIndex = button === target ? 0 : -1
  }

  choose(name) {
    const emote = emotes().find((candidate) => candidate.name === name)
    const controller = this.controller
    this.controller = null
    this.element.close()
    // Inserted straight away, not from the close event (which fires
    // asynchronously), so the emote is in the field the moment the dialog's
    // gone. close() has already restored focus to the emote button by now;
    // inserting moves it on to the field.
    if (emote && controller?.element.isConnected) controller.insertFromPicker(emote)
  }

  // Closed without choosing: Escape, the close button, or the backdrop.
  onClose() {
    const controller = this.controller
    this.controller = null
    if (controller?.element.isConnected) controller.restoreFocus()
  }

  // A click on the backdrop lands on the <dialog> element itself, outside
  // its box.
  onDialogClick(event) {
    if (event.target !== this.element) return
    const rect = this.element.getBoundingClientRect()
    const inside = event.clientX >= rect.left && event.clientX <= rect.right &&
      event.clientY >= rect.top && event.clientY <= rect.bottom
    if (!inside) this.element.close()
  }

  onSearchKeydown(event) {
    const first = this.allButtons()[0]
    if (!first) return
    if (event.key === "ArrowDown") {
      event.preventDefault()
      first.focus()
    } else if (event.key === "Enter") {
      event.preventDefault()
      this.choose(first.dataset.emote)
    }
  }

  // Left/Right move through emotes in order, across group boundaries.
  // Up/Down move to the nearest emote in the row above or below, found by
  // position since each group's grid has its own rows; Up from the top row
  // goes back to the search box.
  onGridKeydown(event) {
    const buttons = this.allButtons()
    const index = buttons.indexOf(document.activeElement)
    if (index === -1) return

    let target
    switch (event.key) {
      case "ArrowRight": target = buttons[Math.min(index + 1, buttons.length - 1)]; break
      case "ArrowLeft": target = buttons[Math.max(index - 1, 0)]; break
      case "ArrowDown": target = nearestInRow(buttons, buttons[index], 1) || buttons[index]; break
      case "ArrowUp":
        target = nearestInRow(buttons, buttons[index], -1)
        if (!target) {
          event.preventDefault()
          this.search.focus()
          return
        }
        break
      case "Home": target = buttons[0]; break
      case "End": target = buttons[buttons.length - 1]; break
      default: return
    }
    event.preventDefault()
    this.setTabStop(target)
    target.focus()
  }
}
