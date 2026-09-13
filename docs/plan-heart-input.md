# Plan: Heart Picker Button + Heart Autocomplete

## Overview

Make heart emoji codes (`:cadbury_heart:`) easy to enter anywhere hearts are rendered, without having to remember names:

1. **Picker button**: a small heart button sits inside the right-hand edge of every heart-capable field. Clicking it opens a dialog showing every heart. Choosing one inserts its code at the caret.
2. **Autocomplete**: like Discord. Typing `:` or `;` followed by at least 2 name characters opens a menu of matching hearts (image + name) next to the caret. Up/Down moves the highlight, Enter (or Tab) inserts it, and Escape dismisses the menu.

Both write the canonical code (`:abyss_heart:`) into the field's plain text value, so the database always stores the original form and nothing server-side changes.

Both features live in **one Stimulus controller** (`heart_input_controller.js`) attached to a wrapper around each field. The controller is named `heart-input`, not `heart-picker`, because `heart_picker_controller.js` already exists: it's the checkbox grid for choosing a profile's own `heart_emojis`.

---

## Step 0: Extract hearts out of `Profile`

Hearts aren't really a profile concern any more. `replace_heart_emojis` calls `Profile.resolve_heart_emoji` for chat messages, server names, channel names, and group names. Five views call `profile.heart_emoji_display_name`. Both new features also need the list. So move everything heart-related into a plain module, in the same style as `ImageDimensions`:

```ruby
# app/models/heart_emoji.rb
module HeartEmoji
  # Order here is the display order everywhere hearts are listed (profile
  # form, picker dialog, autocomplete tiers). Numbers are not part of the
  # canonical name — Discord's numbering churns as hearts are added.
  ALL = [ "dewdrop_heart", ... ].freeze

  # Delimiters (: or ;) and the internal word separator (_ or -) can each be
  # mixed independently, e.g. :cadbury_heart:, ;cadbury-heart;, :cadbury_heart;
  PATTERN = /[:;]([a-z0-9_-]+[_-]heart)[:;]/i

  def self.resolve(name)       # was Profile.resolve_heart_emoji
  def self.display_name(name)  # was Profile.heart_emoji_display_name
  def self.image_path(name)    # "/images/hearts/#{name}.webp", currently repeated in 7 places
  def self.code(name)          # ":#{name}:", the canonical form that gets inserted
end
```

What changes:

- **`Profile`** keeps only what belongs to the profile: the `heart_emojis=` / `mini_profile_heart_emojis=` normalising setters and the two validations. These now use `HeartEmoji.resolve` and `HeartEmoji::ALL`. `Profile::HEART_EMOJIS` and both `heart_emoji_display_name` methods are removed outright, with no aliases, because every caller is in this repo.
- **`ApplicationHelper`** drops `HEART_EMOJI_PATTERN` in favour of `HeartEmoji::PATTERN`, and uses `HeartEmoji.resolve` / `.display_name` / `.image_path` in `replace_heart_emojis` and `plain_field`.
- **Views** switch to `HeartEmoji::ALL`, `HeartEmoji.display_name(heart)` and `HeartEmoji.image_path(heart)`. The same "list a profile's hearts" `image_tag` block appears in five views (`our/profiles/show`, `profiles/show`, `group_profiles/show`, `groups/_profile_content`, `chat/mini_profiles/_mini_profile`) plus `our/chat_identities/edit`. It becomes a `shared/_heart_list` partial.
- **Tests:** the heart tests in `test/models/profile_test.rb` (resolve, display name, well-formed list) move to `test/models/heart_emoji_test.rb`. Profile keeps its validation and setter tests.

This is a pure refactor with no behaviour change, so the existing test suite is the safety net. It ships as its own PR before the features below.

---

## Which fields get it

Every free-text field that is later rendered through `formatted_inline` / `formatted_description` (these are the helpers that call `replace_heart_emojis`):

| Form | Fields |
|---|---|
| `our/profiles/_form` | name, subtitle, pronouns, tag_line, description |
| `our/groups/_form` | name, subtitle, pronouns, tag_line, description |
| `our/chat_identities/_field_toggle` (override input) | name, subtitle, pronouns, tag_line, description |
| `chat/servers/_form` | name, subtitle, description |
| `chat/channels/_form` | name, subtitle, description |
| `chat/channels/show` composer | body |

These fields are **not** included, because hearts aren't rendered in them: labels, chat proxy brackets, theme name/credit/notes, avatar alt text, search boxes, and account fields.

---

## Heart data for JavaScript

`HeartEmoji::ALL` stays the single source of truth. A helper renders it once in `layouts/_head.html.haml`, keeping the order:

```ruby
# ApplicationHelper
def heart_emojis_json_tag
  data = HeartEmoji::ALL.map { |h| { name: h, label: HeartEmoji.display_name(h) } }
  tag.script(data.to_json.html_safe, type: "application/json", id: "heart-emojis")
end
```

That's about 50 short entries, so rendering it in every layout is cheap and avoids per-page `content_for` bookkeeping. The controller reads and parses it once (a module-level cache) and builds image URLs as `/images/hearts/#{name}.webp`, the same way `replace_heart_emojis` does.

CSP is currently all commented out, so an inline JSON `<script>` is fine. If CSP is enabled later, a `type="application/json"` block isn't executed, so it won't need a nonce.

---

## View helper

Views shouldn't repeat the wrapper and button markup, so add a helper:

```ruby
# heart_field(form, :subtitle)
# heart_field(form, :description, as: :text_area, rows: 18)
# heart_field(form, :body, as: :text_area, menu_placement: "above", data: {...})
def heart_field(form, method, as: :text_field, menu_placement: "below", **options)
  field_data = (options.delete(:data) || {}).merge("heart-input-target": "field")
  tag.div(class: "heart-input heart-input--#{as == :text_area ? 'area' : 'line'}",
          data: { controller: "heart-input", "heart-input-placement-value": menu_placement }) do
    safe_join([
      form.public_send(as, method, **options, data: field_data),
      tag.button(type: "button", class: "heart-input__button", hidden: true,
                 "aria-label": "Insert a heart", "aria-haspopup": "dialog",
                 data: { action: "heart-input#openPicker" }) { heart_button_icon }
    ])
  end
end
```

- The field keeps its normal id, so the existing `form.label` associations and Capybara `fill_in "Name"` still work.
- The button starts `hidden` and the controller unhides it on connect. Without JS there's no dead button, and the field works exactly as it does today.
- Existing `data` passed in is merged, not replaced. This matters for the composer textarea, which carries `composer-target` and `composer#…` actions.
- `_field_toggle` switches from `form.public_send(input_type, …)` to `heart_field(form, override_field, as: input_type, …)`.

---

## Feature 1: Picker button and dialog

### Button placement (CSS)

- `.heart-input { position: relative; }`
- Single-line fields: the button is absolutely positioned at the right, vertically centred. The input gets `padding-right` so text never runs under the button.
- Textareas: the button sits at the top-right corner, clear of the resize handle at the bottom right. The textarea gets extra `padding-right`.
- Composer: centred on the right of the one-line auto-growing textarea, with colours from the `--chat-composer-*` tokens.
- Icon: a neutral heart SVG using `currentColor`, so it follows every theme and forced-colors mode. It shouldn't be one of the coloured webp hearts, which would clash with some themes.

### One shared dialog per page

A single `<dialog class="heart-dialog">` is built by JS on first open, appended to `<body>`, and reused by every field on the page. This means:

- Fifty images aren't duplicated across up to 12 fields.
- The dialog sits **outside** any `<form>`, so its buttons can never accidentally submit (unlike the avatar dialog, which has to live inside the form).

Contents:

- A title ("Choose a heart") and a close button.
- A **search input**, focused on open, which uses the same matching function as autocomplete (below).
- A grid of `<button type="button">` items, each showing a 32px image with its name underneath. Keeping the name visible makes the dialog a way to learn names for autocomplete.
- Images use `loading="lazy"`.
- Arrow keys move focus around the grid (roving tabindex), and Enter/Space chooses.

### Insertion flow

1. `openPicker` saves the field's `selectionStart`/`selectionEnd`, records which field opened the dialog, and calls `showModal()`.
2. Choosing a heart inserts `:name_heart:` at the saved selection, replacing any selected text. See [Inserting text](#inserting-text).
3. The dialog closes, focus returns to the field, and the caret lands after the inserted code.
4. Escape, the close button, or a click on the backdrop closes the dialog without inserting, and focus returns to the field.

---

## Feature 2: Autocomplete

### Trigger

On `input` (and on `click`/`keyup` for caret moves), look at the text **before the caret**:

```js
const TRIGGER = /(?:^|[^\p{L}\p{N}_:;])([:;])([\p{L}\p{N}_-]{2,})$/u
```

- The delimiter must be at the start of the text or follow a character that isn't a letter, number, or delimiter. This avoids false positives such as `10:30`, `https://ab…`, `note:ab`, and `::ab`.
- At least 2 name characters are required, so `:)` and `;-;` never trigger.
- The menu only opens if at least one heart matches. `;ok` does nothing.
- Once a closing `:`/`;` or a space is typed, the pattern no longer matches, so the menu closes by itself.
- Nothing triggers inside an IME composition (`event.isComposing`).

### Matching and ordering

Normalise the query by lowercasing it, converting `-` to `_`, and stripping a leading number prefix (`11_aq` → `aq`) to match `Profile.resolve_heart_emoji`. Then compare against each heart:

1. **Starts-with tier**: the full name starts with the query. Using the full name means `;abyss_he` still finds abyss.
2. **Contains tier**: the base name (without `_heart`) contains the query anywhere, as a contiguous substring. Using the base name means `;he` doesn't match all 50 hearts through their `_heart` suffix.

Within each tier, hearts stay in `HeartEmoji::ALL` order (the same order as the profile form and the picker dialog). The first item is highlighted.

Example: `;ab` → **abyss** (highlighted, starts-with), then **vulnerable** (contains "ab").

The list scrolls after about 8 visible rows. The same function also filters the dialog's search box.

### Menu

- A single `<ul role="listbox">` per controller is built lazily inside `.heart-input`. Each `<li role="option">` holds a 24px image and the display name ("abyss heart").
- **Position:** the menu opens at the caret, using the standard mirror-div technique. A hidden div copies the field's font, padding, and width plus the text up to the caret, and a marker span gives the caret's x/y. This matters for the 18-row description textarea, where a menu anchored to the field would appear far from where the user is typing.
  - `placement: "below"` (forms): the menu appears below the caret line.
  - `placement: "above"` (composer): the menu appears above, like the posting-as dropdown, because the composer is pinned to the bottom of the viewport.
  - The menu is clamped to the field's width, and on narrow screens it spans the full width of the field.
- **Mouse/touch:** `pointerdown` on an option calls `preventDefault()` so the field keeps focus, and a click inserts the heart. Hovering doesn't move the highlight, so a resting mouse can't fight the arrow keys.
- The menu closes on blur, Escape, or when the trigger stops matching. After Escape, it stays closed until the query text changes, so it doesn't pop straight back open.

### Keyboard

While the menu is open:

| Key | Action |
|---|---|
| ↓ / ↑ | Move the highlight, wrapping at the ends, and scroll the item into view |
| Enter / Tab | Insert the highlighted heart |
| Escape | Close the menu |

When the menu is closed, these keys do nothing special.

**Conflict with the composer's Enter-to-send:** `composer#submitOnEnter` is a keydown action on the textarea itself. The heart-input controller listens for `keydown` in the **capture phase on its wrapper**. Capture listeners on an ancestor always run before listeners on the target, whatever order Stimulus wires things up in. When it handles a key, it calls `preventDefault()`. `submitOnEnter` gets one extra line:

```js
if (event.defaultPrevented) return
```

The chat identity form's Enter handling (if any) needs the same check.

### Insertion

The typed `;ab` (from the delimiter to the caret) is replaced with `:abyss_heart:`:

- **Always the canonical colon form**, even when triggered with `;`. Inserting doesn't need Shift, and stored text stays consistent. The picker dialog uses the same form.
- **A trailing space is added** unless the next character is already whitespace. The same applies to picker insertions.

---

## Inserting text

Both features share one method:

```js
insert(field, start, end, text) {
  field.focus()
  field.setSelectionRange(start, end)
  // execCommand keeps the browser's native undo stack (Ctrl+Z works) and
  // fires a real `input` event; setRangeText is the fallback.
  if (!document.execCommand("insertText", false, text)) {
    field.setRangeText(text, start, end, "end")
    field.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
```

The `input` event matters: the composer's `autoGrow` and `detectProxy`, and the chat identity live preview, all listen for it.

---

## Accessibility

- The field gets `aria-autocomplete="list"`, `aria-controls` pointing at the listbox, and `aria-expanded`. It also gets `aria-activedescendant` set to the highlighted option's id.
- A visually hidden `aria-live="polite"` region announces "3 hearts found, abyss heart selected" when the menu opens, and the new name when the highlight moves.
- The picker button is a real `<button>` with `aria-label="Insert a heart"`, and the dialog uses native `showModal()`, which traps focus.
- Images in options have `alt=""` because the visible name is the label.
- The design fits the existing semicolon/hyphen work: people who can't press Shift can type `;ab`, arrow down, and press Enter.
- Forced-colors mode: the highlight uses `Highlight`/`HighlightText` system colours inside `@media (forced-colors: active)`.

---

## Bonus: showing hearts inside the field

Native `<input>`/`<textarea>` elements can only display plain text, so a heart image can't appear inside them. The options are:

1. **Replace fields with `contenteditable`** (Discord's approach). This would let images show inline, but it means rebuilding caret handling, paste sanitising, undo, mobile keyboards, form submission through hidden inputs, screen reader support, and every Capybara `fill_in`. **Not recommended**: the cost is high and so is the risk of breaking basic typing.
2. **Live preview strip under the field (recommended if wanted).** Once a field contains at least one valid heart code, a small line under it shows the text with codes swapped for images. This is client-side only: the same regex as `HEART_EMOJI_PATTERN`, validated against the JSON list, building DOM nodes rather than HTML strings so nothing needs sanitising. It's hidden when there are no hearts, and it's cheap and safe. The chat identity page already has a preview panel, so this might only be worth doing for the profile/group forms and the composer.

This should be a separate follow-up phase, not part of the first PR.

---

## Files

**Step 0 (extraction)**
- New: `app/models/heart_emoji.rb`, `app/views/shared/_heart_list.html.haml`, `test/models/heart_emoji_test.rb`
- Changed: `app/models/profile.rb`, `app/helpers/application_helper.rb`, `test/models/profile_test.rb`, `our/profiles/_form`, `our/profiles/show`, `profiles/show`, `group_profiles/show`, `groups/_profile_content`, `chat/mini_profiles/_mini_profile`, `our/chat_identities/edit`

**Features: new**
- `app/javascript/controllers/heart_input_controller.js`
- `test/system/heart_input_test.rb`

**Features: changed**
- `app/helpers/application_helper.rb`: `heart_emojis_json_tag`, `heart_field`, `heart_button_icon`
- `app/views/layouts/_head.html.haml`: render the JSON tag
- `app/views/our/profiles/_form.html.haml`, `our/groups/_form.html.haml`, `chat/servers/_form.html.haml`, `chat/channels/_form.html.haml`: use `heart_field`
- `app/views/our/chat_identities/_field_toggle.html.haml`: use `heart_field` for the override input
- `app/views/chat/channels/show.html.haml`: wrap the composer textarea
- `app/javascript/controllers/composer_controller.js`: `defaultPrevented` guard
- `app/assets/stylesheets/application.css`: `.heart-input`, `__button`, `__menu`, `__option`, `.heart-dialog`, plus composer and forced-colors variants
- `test/helpers/application_helper_test.rb`: JSON tag and `heart_field` markup

No migrations and no model or controller changes.

---

## Tests

**Helper tests**
- The JSON tag lists every `HeartEmoji::ALL` entry, in order.
- `heart_field` keeps the field id, merges passed `data`, and renders the button `hidden`.

**System tests** (`heart_input_test.rb`)
- Picker: open the dialog from the profile subtitle field, click "abyss heart", and check the field value contains `:abyss_heart:` at the caret. Save and check the stored value is canonical and the show page renders the image.
- Picker search: typing "vul" filters the grid down to vulnerable.
- Picker cancel: Escape inserts nothing and returns focus to the field.
- Autocomplete: typing `;ab` opens the menu with abyss first and highlighted, and vulnerable present. Enter inserts `:abyss_heart: ` (colon form, trailing space) and closes the menu.
- Autocomplete ordering: a query matching several hearts in the same tier lists them in `HeartEmoji::ALL` order.
- Autocomplete arrows: `;ab`, then ↓, then Enter inserts `:vulnerable_heart:`.
- Autocomplete dismissal: `;ab`, then Escape closes the menu and leaves `;ab` untouched.
- No false triggers: typing `10:30` or `https://ab` shows no menu.
- Composer: with the menu open, Enter inserts the heart and **does not send**. With the menu closed, Enter still sends.
- Description textarea: autocomplete works mid-text on a later line.

---

## Suggested phasing

0. **PR 0:** Extract `HeartEmoji` out of `Profile`. This is a pure refactor.
1. **PR 1:** JSON data tag, `heart_field` helper wired into all the forms, picker button and dialog. This is useful on its own and sets up the wrapper everything else hangs off.
2. **PR 2:** Autocomplete menu, including caret positioning, keyboard handling, the composer guard, and ARIA.
3. **PR 3 (optional):** Live preview strip.

---

## Decisions

1. **Delimiter on insert:** always the canonical colon form (`:abyss_heart:`), even when autocomplete was triggered with `;`.
2. **Trailing space:** added after an inserted heart, unless the next character is already whitespace.
3. **Order within a tier:** `HeartEmoji::ALL` order, not alphabetical.
4. **Matching:** the query must appear as a contiguous substring (`ab` in vulnerable), which is what Discord does.
5. **Extraction:** hearts move out of `Profile` into a `HeartEmoji` module first (Step 0).
