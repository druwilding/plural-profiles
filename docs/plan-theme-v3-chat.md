# Plan: Themes v3 — A Separate Colour Set for Chat

## Summary

Chat currently borrows the profile-page palette wholesale. Every chat region —
the server rail, the channel sidebar, the channel header, the message pane, the
composer — is painted from the same four variables (`--pane-bg`, `--pane-text`,
`--pane-title-text`, `--pane-border`), so a theme designer has no way to make
the rail a different colour from the dividers, or the message pane a different
colour from the channel list.

This plan adds a **chat colour set**: a second group of themeable properties,
prefixed `chat_`, consumed only by chat-scoped CSS. Any chat property that the
designer hasn't explicitly set **inherits** from its profile-page equivalent, so
every existing theme keeps its current appearance with no migration and no action
from its author. The one deliberate exception is background images, which stop
appearing on chat pages (see Phase 2).

## Decisions

| Question               | Decision                                                                                                                                                                                                                   |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| New properties         | 28 `chat_*` keys across 6 regions (full table below)                                                                                                                                                                       |
| Inheritance model      | **One-directional**: profile is primary and always set; chat is secondary and either inherits or overrides. Confirmed, not bidirectional — see [Why one-directional](#why-one-directional)                                 |
| Storage of "inherited" | **Key absent from `colors`** — no extra column, no sentinel value                                                                                                                                                          |
| Fallback resolution    | **In Ruby**, inside `Theme#color_for`, which walks a `fallback:` chain                                                                                                                                                     |
| Data migration         | **None.** Fallbacks make every existing theme render identically today (bar the background-image change below), and keep chat tracking later profile edits. A migration would freeze current values and defeat the feature |
| Editor UX              | Per-property **"Override" checkbox** that enables the picker; unticked, the colour follows its profile counterpart                                                                                                         |
| Export version         | Bump `CURRENT_EXPORT_VERSION` to `3`; keep accepting 1–3                                                                                                                                                                   |
| Preview                | Tabbed preview pane: **Profile** (today's preview) / **Chat** (new mock)                                                                                                                                                   |
| Background images      | **Never shown in chat.** Chat pages get flat `chat_page_bg` only — see [Phase 2](#phase-2-drop-background-images-from-chat)                                                                                                |
| Theme swatches         | **Unchanged.** `SWATCH_PROPERTIES` stays profile-only; no chat swatch row on theme cards                                                                                                                                   |
| Theme resolution       | **Unchanged.** The most relevant theme wins whether or not it defines chat colours — inheritance is always *within* one theme, never across themes                                                                         |

### Why one-directional

The original request said "if only one of those has been designed, the colours
from the designed one are auto-inherited onto the undesigned one", which would
imply chat → profile too. Confirmed as **one-directional**: profile is primary
and always set, chat is secondary and either inherits or overrides.

This is also the only direction the data can actually express. Every theme
already carries a complete profile set backed by hard-coded defaults, so "the
profile side is undesigned" is indistinguishable from "the profile side is
deliberately the stock green". Reversing the flow would mean making profile keys
optional too and adding a "which side is canonical?" flag — a much larger change
for a state no theme is currently in.

The practical consequence: **`fallback:` only ever appears on `chat_*` keys.**
Profile keys keep their current behaviour exactly — stored value, else default —
so the chain always terminates on the profile side. That's worth asserting in a
test (see Phase 6).

---

## Current state

### How a theme reaches the page

1. `Theme::THEMEABLE_PROPERTIES` ([theme.rb:93](../app/models/theme.rb#L93)) declares
   every themeable key with a `label`, a hex `default`, and a `group`.
2. `Theme#color_for(prop)` returns the stored value, or the property's `default`.
3. `Theme#to_css_properties` emits **every** key as a concrete `--foo: #hex;`
   string, plus the two `DERIVED_TEXT_PROPERTIES` pre-resolved.
4. `ThemeHelper#active_theme_style` picks the winning theme
   (`@channel_theme || @server_theme || @group_theme || @profile_theme`, or the
   user's own with override on) and puts that string in `<body style="">`.
5. `:root` in [application.css:9](../app/assets/stylesheets/application.css#L9)
   holds the same keys as hard defaults for logged-out visitors.

**Important constraint already documented in the codebase**
([theme.rb:192-210](../app/models/theme.rb#L192)): a `var()` reference *inside a
custom property declared at `:root`* is resolved at `:root`, not re-resolved
per-element. So `:root { --chat-pane-bg: var(--pane-bg) }` would **not** follow a
`--pane-bg` override set on `body`. This is why fallbacks are resolved in Ruby
and emitted concretely, and why the new `:root` defaults must be literal hexes
rather than `var()` references. (`var()` inside an ordinary property such as
`background-color` is fine — that resolves per-element — which is what all the
existing `color-mix(in srgb, var(--pane-text) …)` rules rely on.)

### What chat actually uses today

Across the chat CSS block (lines ~3616–4500) there are only **8 distinct themed
variables**, and `--pane-text` alone accounts for 25 of the ~46 usages:

| Variable                | Uses | Regions it paints                                                                                                 |
| ----------------------- | ---- | ----------------------------------------------------------------------------------------------------------------- |
| `--pane-text`           | 25   | rail icons, channel labels, message body, timestamps, pronouns, every hover/`color-mix` tint                      |
| `--pane-border`         | 7    | rail background, channel-sidebar right border, channel-header bottom border, composer top border, unread-dot ring |
| `--pane-bg`             | 3    | channel sidebar, message pane, "posting as" pill                                                                  |
| `--pane-title-text`     | 3    | server name, active channel, message author names                                                                 |
| `--pane-link`           | 3    | "+ Add channel", rail add button, focus rings                                                                     |
| `--page-bg`             | 2    | picker search field                                                                                               |
| `--tree-guide`          | 1    | date-divider rules                                                                                                |
| `--primary-button-text` | 1    | unread dots                                                                                                       |

That table is the whole problem in miniature. `--pane-border` doing double duty
as *both* the rail background *and* every divider line is exactly the complaint
that "the server-list sidebar can't be a different colour to the border bars";
`--pane-bg` doing double duty for the channel sidebar and the message pane is
"the various chat panes are all forced to be the same colour"; and
`--pane-title-text` spanning the sidebar server name, the channel header title,
and message author names is the text-crossover complaint.

### An existing precedent worth reusing

`ChatIdentity` ([chat_identity.rb](../app/models/concerns/chat_identity.rb))
already solves "chat has its own version of this, inheriting from the main one
unless overridden", with a `chat_<field>` reader resolving the inherit/override
decision in exactly one place, and a **"Use main" / "Set for chat"** radio pair
in the editor ([_field_toggle.html.haml](../app/views/our/chat_identities/_field_toggle.html.haml)).
Themes v3 should look and feel like the same feature, because to a user it *is*
the same idea applied to colour.

---

## Phase 1: Property schema and fallback resolution

### `THEMEABLE_PROPERTIES` gains a `fallback:`

```ruby
"chat_pane_bg" => { label: "Message pane background", default: "#133b2f",
                    group: :chat_pane, fallback: "pane_bg" },
```

### `color_for` walks the chain

```ruby
# Resolves a property to a concrete colour. A chat_* property the designer
# hasn't set falls back to its profile-page equivalent (and so on up the
# chain), so a theme designed only for profiles still paints chat sensibly —
# and keeps tracking later edits to the profile colours, which a one-time
# migration of the values could never do.
def color_for(property, seen = nil)
  key = property.to_s
  stored = colors&.dig(key)
  return stored if stored.present?

  meta = THEMEABLE_PROPERTIES[key]
  return nil unless meta

  if (parent = meta[:fallback])
    seen ||= Set.new
    return meta[:default] unless seen.add?(key) # cycle guard
    return color_for(parent, seen)
  end

  meta[:default]
end
```

The cycle guard is cheap insurance: the chains are hand-written in a constant,
and a typo that makes one point at itself would otherwise be an infinite loop in
a request.

Everything downstream (`to_css_properties`, `to_css`, `swatch_colors`, the form,
the preview) already goes through `color_for` and needs no change.

### Two-level grouping

`PROPERTY_GROUPS` becomes a nested structure so the editor can render two
top-level sections:

```ruby
PROPERTY_SECTIONS = {
  profile: { label: "Profile pages", groups: %i[page header pane forms buttons flash] },
  chat:    { label: "Chat",          groups: %i[chat_page chat_header chat_rail chat_dividers
                                                chat_sidebar chat_topbar chat_pane chat_composer] }
}.freeze
```

Keep `PROPERTY_GROUPS` as the flat `group_key => label` map it is today; only
add the section layer on top. That keeps `test/models/theme_test.rb:127`
("covers all expected groups") meaningful and the form loop nearly unchanged.

### The full key table

Every `default` below is **the value that region renders today** for the stock
theme, so `:root` and the model defaults agree with current appearance.

#### Chat · Page (1)

| Key            | Falls back to | Paints                                                     |
| -------------- | ------------- | ---------------------------------------------------------- |
| `chat_page_bg` | `page_bg`     | `.chat-body` — visible behind server list / settings cards |

#### Chat · Page header bar (4)

Scoped `.chat-body .site-header …`, so the same markup renders differently in
chat and on profile pages.

| Key                      | Falls back to       | Paints                            |
| ------------------------ | ------------------- | --------------------------------- |
| `chat_header_bg`         | `header_bg`         | `.site-header` background         |
| `chat_header_title_text` | `header_title_text` | the "Plural Profiles" logo text   |
| `chat_header_text`       | `header_text`       | header body text, domain switcher |
| `chat_header_link`       | `header_link`       | "Sign out", nav links             |

#### Chat · Server sidebar (3)

| Key                | Falls back to     | Paints                                                                                                  |
| ------------------ | ----------------- | ------------------------------------------------------------------------------------------------------- |
| `chat_rail_bg`     | `pane_border`     | `.server-rail` background (**this is the key fix** — the rail stops being welded to the divider colour) |
| `chat_rail_text`   | `pane_text`       | rail icon colour, hover ring, the dashed "+" button border, `.unread-dot--rail` ring                    |
| `chat_rail_active` | `pane_title_text` | the active-server ring (`box-shadow` on `.server-rail__icon--active`)                                   |

#### Chat · Divider bars (1)

| Key            | Falls back to | Paints                                                                                                                              |
| -------------- | ------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `chat_divider` | `pane_border` | `.channel-pane` right border, `.chat-channel-header` bottom border, `.composer` top border, `.chat-body .site-header` bottom border |

#### Chat · Channel sidebar (4)

| Key                       | Falls back to     | Paints                                                               |
| ------------------------- | ----------------- | -------------------------------------------------------------------- |
| `chat_sidebar_bg`         | `pane_bg`         | `.channel-pane`                                                      |
| `chat_sidebar_text`       | `pane_text`       | channel labels, plus every `color-mix` hover/active tint in the pane |
| `chat_sidebar_title_text` | `pane_title_text` | `.channel-pane__server-name`, active channel label                   |
| `chat_sidebar_link`       | `pane_link`       | "+ Add channel"                                                      |

#### Chat · Chat header (3)

| Key                      | Falls back to     | Paints                                                                                     |
| ------------------------ | ----------------- | ------------------------------------------------------------------------------------------ |
| `chat_topbar_bg`         | `pane_bg`         | `.chat-channel-header` (today it has no background of its own — it shows the pane through) |
| `chat_topbar_text`       | `pane_text`       | channel description, subtitle                                                              |
| `chat_topbar_title_text` | `pane_title_text` | the `# channel-name` `h1`                                                                  |

Every fallback points **straight at a profile key** — no chat colour follows
another chat colour. An earlier draft chained the header through
`chat_pane_bg`, on the theory that re-tinting the message pane should drag the
header along with it; in practice that made "what is this actually following?"
something you had to trace instead of read. Each chat colour now follows one
profile colour and nothing else, enforced by a model test.

#### Chat · Message pane (5)

| Key                    | Falls back to     | Paints                                                                              |
| ---------------------- | ----------------- | ----------------------------------------------------------------------------------- |
| `chat_pane_bg`         | `pane_bg`         | `.chat-main:has(.chat-channel)`                                                     |
| `chat_pane_text`       | `pane_text`       | message bodies, timestamps, pronouns, date dividers, the `.chat-date-divider` rules |
| `chat_pane_title_text` | `pane_title_text` | `.chat-message__name`                                                               |
| `chat_pane_link`       | `pane_link`       | links inside messages, `.profile-picker__option:focus-visible`                      |
| `chat_spoiler`         | `spoiler`         | spoilers in messages                                                                |

#### Chat · Composer bar (6)

| Key                       | Falls back to  | Paints                                       |
| ------------------------- | -------------- | -------------------------------------------- |
| `chat_composer_bg`        | `pane_bg`      | `.composer`                                  |
| `chat_composer_text`      | `pane_text`    | composer text and its `color-mix` tints      |
| `chat_composer_highlight` | `pane_bg`      | `.profile-picker` pill background and border |
| `chat_input_bg`           | `input_bg`     | composer textarea, `.profile-picker__search` |
| `chat_input_border`       | `input_border` | composer textarea border                     |
| `chat_input_text`         | `input_text`   | composer textarea text                       |

`chat_composer_highlight` is the one property with no exact current equivalent:
`.profile-picker` is `color-mix(in srgb, var(--pane-bg) 85%, var(--page-bg) 15%)`
today. Give it a concrete hex default computed from the stock theme (≈`#12372c`)
rather than a mix, so the picker in the editor shows a real swatch. The visual
delta on existing themes is a hair's breadth, but it is non-zero — worth a
sentence in the changelog.

The three `chat_input_*` keys are the ones the users called "not as essential";
they come almost free once the chain machinery exists, and they follow
`input_*` exactly until touched.

### Derived properties

`DERIVED_TEXT_PROPERTIES` currently maps css-prop → percent, always sourced from
`pane_text`. Generalise it to name its source:

```ruby
DERIVED_TEXT_PROPERTIES = {
  "tree-guide"                     => { source: "pane_text",      percent: 30 },
  "avatar-placeholder-border"      => { source: "pane_text",      percent: 50 },
  "chat-tree-guide"                => { source: "chat_pane_text", percent: 30 },
  "chat-avatar-placeholder-border" => { source: "chat_pane_text", percent: 50 }
}.freeze
```

These two are the *only* derived values that need chat twins, because they are
the only ones declared as custom properties at `:root`. Every other tint in chat
is an inline `color-mix()` in an ordinary property, which re-resolves per element
— swapping `var(--pane-text)` for `var(--chat-pane-text)` in those rules is
sufficient and needs no Ruby involvement.

`theme_designer_controller.js` reads this hash from a data attribute; update
`applyToPreview` to fire on *either* source key rather than hardcoding
`pane_text`. Its `test/models/theme_test.rb:111` counterpart iterates the
constant, so it keeps passing.

---

## Phase 2: Drop background images from chat

**This is the one place the plan deliberately changes how an existing theme
renders.** Today `ThemeHelper#theme_style_string` appends
`background_css_properties` to the body style for *every* layout, chat included
— so a theme with a background image currently shows it behind the server list,
the server/channel settings pages and the invite pages. (Not behind the messages
themselves: `.chat-main:has(.chat-channel)` paints an opaque `--pane-bg` over
it.) Chat should have no background image at all; `chat_page_bg` is the flat
colour behind those pages instead.

Implement it in the helper rather than the stylesheet:

```ruby
def active_theme_style(background_image: true)
  # … unchanged resolution …
  theme_style_string(theme, background_image: background_image)
end

def theme_style_string(theme, background_image: true)
  return unless theme
  style = theme.to_css_properties
  if background_image && theme.background_image.attached?
    url = rails_storage_proxy_url(theme.background_image)
    style += " #{theme.background_css_properties(url)}"
  end
  style
end
```

with `layouts/chat.html.haml` passing `active_theme_style(background_image: false)`.

A `.chat-body { background-image: none !important }` rule in the stylesheet would
also work — `!important` in a stylesheet does beat a non-important inline
declaration — but it's worse on three counts: it leaves four orphaned
`background-repeat/size/position/attachment` declarations that no longer mean
anything, it hides the intent somewhere nobody reading `ThemeHelper` will find
it, and it still calls `rails_storage_proxy_url` on every chat page, minting a
signed URL for an image that is never fetched.

Two follow-ons:

- The **Background image** section of the theme form should say it applies to
  profile pages only, so nobody spends an afternoon wondering why their tiled
  texture never reaches chat.
- The **chat preview mock** must not paint the background image, even though the
  profile preview does. Since both live inside the same `.theme-preview`
  element, the chat tab needs its own opaque `chat_page_bg` layer rather than
  inheriting the preview container's background.

---

## Phase 3: CSS

Add the chat keys to `:root` as **literal hexes** (not `var()` references — see
the constraint above; the existing `--input-text: var(--pane-text)` line is a
latent version of exactly the bug that `to_css_properties` works around, and
this plan should not add 27 more of them).

Then rewrite the chat block, region by region. It's mechanical — roughly 46
variable references across ~880 lines — but three spots need care:

1. **`.chat-body .site-header`** — new scoped overrides. Must beat the base
   `.site-header` rules (specificity 0,2,0 vs 0,1,0 — fine) and cover
   `.site-header .logo`, `.site-header nav a`, `.site-header nav .link-button`,
   and the bottom border.
2. **`.server-rail__icon--active`** — its ring is
   `box-shadow: 0 0 0 2px var(--pane-border), 0 0 0 4px var(--pane-title-text)`.
   The *inner* 2px is a spacer that must match the rail background, so it
   becomes `var(--chat-rail-bg)`, not `var(--chat-divider)`. Same for
   `.unread-dot--rail`'s border. Getting this wrong is invisible on themes where
   the two still match and obviously broken on themes where they don't — which
   is precisely the themes this feature exists for.
3. **`.chat-main .card`** — the chat layout also renders plain pages (server
   list, server/channel settings, invites) whose cards use `--pane-bg` /
   `--pane-text`. Point those at the chat set too, so chat settings pages match
   the chat theme rather than snapping back to the profile palette mid-session.

The `@media (forced-colors: active)` blocks need no changes: they replace themed
colours with system keywords, which is orthogonal to which variable was there.

---

## Phase 4: Editor

### Section structure

Wrap the existing colour groups in a `Profile pages` accordion and add a `Chat`
accordion beside it, driven by `PROPERTY_SECTIONS`. Each chat group is a
`<details>` exactly as today.

### Per-property inherit toggle

Each chat property renders a radio pair modelled on
`our/chat_identities/_field_toggle`:

```
Message pane background          ( • ) Use profile colour   (   ) Set for chat
  ▸ inheriting  #133b2f  from "Pane background"
```

Storage rule: **"Use profile colour" means the key is absent from `colors`**.
Mechanically, the Stimulus controller sets `disabled` on *both* the
`input[type=color]` and the hex text input when "Use profile colour" is
selected — disabled controls don't submit, and since `update` replaces the whole
`colors` hash, a previously-set value is dropped cleanly with no extra code.

Three details that will bite otherwise:

- Each property currently posts `theme[colors][x]` **twice** (colour input and
  hex input, last-wins). Both must be disabled together, or the field still posts.
- Coloris wraps the hex input in a `.clr-field` and hides the native colour
  input. Disabling must also stop the Coloris popup opening — `disabled` on the
  underlying input is respected, but the generated `.clr-field button` needs
  `disabled` and `pointer-events: none` too.
- The greyed-out field should display the **resolved inherited colour**, updating
  live when its parent changes. That's just "when a property changes, re-apply
  every property that inherits from it" — build a reverse index of the chain
  once at `connect()`.

### Preview

Add a tab strip above the preview pane: **Profile** (today's `_preview`) /
**Chat** (new `_chat_preview`).

The chat mock renders **the real class names** — `.server-rail`,
`.channel-pane`, `.chat-channel-header`, `.chat-message`, `.composer`,
`.profile-picker` — inside a `.theme-preview__chat` wrapper, with a small
scoped block that neutralises only the *layout* rules (`height: 100dvh`,
`flex: 1`, `overflow`, the 72px/200px fixed widths) while every colour rule
applies untouched. That is what keeps the preview honest: if a colour rule is
added to chat later and the preview doesn't show it, the mock is missing
markup, not a divergent copy of the stylesheet.

The preview column is roughly half the designer's width, so shrink the rail and
sidebar in the preview scope (say 48px / 140px) and show two messages, a date
divider, and the posting-as pill — enough to exercise every key in the table.

`.theme-preview__header` and `.theme-preview__logo` already exist in the CSS but
are **used by no view** — dead rules from an earlier revision. Either delete them
or reuse them for the chat mock's header bar; don't leave them orphaned.

---

## Phase 5: Import / export

- Bump `CURRENT_EXPORT_VERSION` to `3`; keep `version.between?(1, 3)`.
- `LEGACY_COLOR_ALIASES` (v1 → v2) is untouched. **There is no v2 → v3 upgrade
  step** — the new keys are purely additive, and "absent" is already the correct
  meaning for a v2 export. That falls out of the fallback design for free.
- `to_export_hash` already emits `colors` as stored, so a theme with no chat
  overrides exports no chat keys. Exports get *smaller* and more legible.
- `theme_import_controller.js`'s CSS parser converts `--chat-pane-bg` →
  `chat_pane_bg` with no change; `importJson` needs none either.
- `theme_designer_controller.js#updateJsonOutput` needs two changes: write
  `plural_profiles_theme: 3`, and **skip disabled hex inputs** so the JSON
  reflects what will actually be stored.
- `Our::ThemesController#new` seeds `colors` from
  `THEMEABLE_PROPERTIES.transform_values { |v| v[:default] }` — i.e. every key
  explicitly set. Change it to seed only the profile keys, so a brand-new theme
  starts fully inherited on the chat side instead of 27 keys pinned to the stock
  green.

---

## Phase 6: Tests

**Model** (`test/models/theme_test.rb`)
- `color_for` returns the stored value when set.
- `color_for` returns the parent's *stored* value when unset (not the parent's default).
- `chat_topbar_bg` with only `pane_bg` set resolves to `pane_bg`.
- **No chat key's fallback is another chat key** — the invariant that keeps
  resolution one hop deep, and `color_for` a lookup rather than a walk.
- Every chat key's default matches its counterpart's, so an untouched theme
  can't drift.
- Every `fallback:` names a real key, and no chain cycles (iterate the constant).
- **Only `chat_*` keys carry a `fallback:`** — this is what pins the inheritance
  to one direction, and it's a one-line assertion over the constant that fails
  loudly the day someone adds a fallback to a profile key by reflex.
- `to_css_properties` emits all chat vars, concretely.
- `DERIVED_TEXT_PROPERTIES` chat entries derive from `chat_pane_text`.
- Export is version 3; a chat-free theme exports no `chat_*` keys.
- Import of a v2 fixture succeeds and stores no chat keys.

**Helper** (`test/helpers/theme_helper_test.rb`)
- `active_theme_style` includes the background-image declarations by default.
- `active_theme_style(background_image: false)` includes the colour custom
  properties but **no** `background-image` / `background-repeat` / `-size` /
  `-position` / `-attachment`.
- A theme with no attachment behaves identically either way.

**Controller** (`test/controllers/our/themes_controller_test.rb`)
- Posting without a `chat_*` key leaves it unstored.
- Posting a `chat_*` key stores it; re-posting without it removes it.
- `#new` seeds no chat keys.
- A chat page rendered with a background-image theme active emits no
  `background-image` in the body style — the regression guard for Phase 2.

**System** (`test/system/themes_test.rb`)
- Switching a chat property to "Set for chat" enables its picker and changes
  only the chat preview.
- Changing `pane_bg` moves an inheriting chat swatch live.
- "Use profile colours for all" clears the section.

**Regression guard worth writing explicitly:** assert that a theme whose
`colors` hash contains *only* the v2 keys produces a `to_css_properties` string
in which each `--chat-*` value equals its profile-side parent. That is the
"existing themes look identical" promise, enforced.

---

## Risk and effort

| Phase                  | Risk     | Notes                                                                                       |
| ---------------------- | -------- | ------------------------------------------------------------------------------------------- |
| 1 · Schema + fallbacks | Low      | Additive; `color_for` is the single chokepoint                                              |
| 2 · No chat bg image   | Low      | Small, but the only user-visible regression — worth a changelog line                        |
| 3 · CSS                | Medium   | ~46 mechanical edits, but the rail-ring and divider spacers are easy to get subtly wrong    |
| 4 · Editor             | **High** | The bulk of the work. Coloris + disabled state + live inherited swatches is the fiddly part |
| 5 · Import/export      | Low      | Mostly a version bump                                                                       |
| 6 · Tests              | Low      |                                                                                             |

Phases 1, 2, 3 and 5 could ship as one PR and would already be useful via pasted
JSON import, with the editor following — but the editor is the whole point for
the users who asked, so shipping them together is probably kinder.

---

## As built

Shipped across six commits on `themes-v3-chat`. Where the implementation
departed from the plan above:

**28 chat keys, not 27.** The plan missed the server rail's "+" button, which
took `--pane-link`. No existing chat key had a matching default, so mapping it
to one of them would have silently recoloured it on every theme. Added
`chat_rail_link` (fallback `pane_link`) instead.

**`chat_sidebar_link` covers channel names.** Channel rows are bare `<a>`s with
no colour rule of their own, so they have always taken the link colour rather
than the pane text colour. The key is labelled "Channel names & links" so
that's findable; `chat_sidebar_text` drives the hover and active tints.

**The picker's search field kept the page colour.** The plan had
`.profile-picker__search` following `chat_input_bg`, but it uses `--page-bg`
today, and `chat_input_bg` defaults to `input_bg` — a different colour. It
follows `chat_page_bg` / `chat_divider` / `chat_composer_text` instead, all
exact-fidelity matches, and `chat_input_*` drives the composer textarea, which
is what actually took `--input-*` before.

**Chat scoping reached further than `.chat-main .card`.** `.card > .card__header`
and `.mini-profile__header` are `--header-bg` banners, and both render inside
chat (settings pages, and the popover behind a message author's name). Left
alone they'd sit on the *profile* header colour in the middle of a chat-themed
page — the exact cross-over this feature exists to fix — so they follow the
chat header keys too.

**`:where(.chat-body) a`, not `.chat-body a`.** At `(0,1,1)` the plain form
outranks every single-class rule colouring a link in chat, flattening the
channel names, "+ Add channel", the rail icons and the back arrow to one
colour. `:where()` contributes no specificity, so it lands at `(0,0,1)` —
identical to the base `a` rule it replaces, and beaten by every class selector,
which is what it needs to be. There's a system test for this specifically.

**`chat_unread_dot` was added after review.** The unread dot had no key of its
own and borrowed `--primary-button-text`; on a theme with dark button text
(drurple's is `#1b0436`) that left it invisible against the rail. It follows
`primary_button_text`, so nothing changes until it's set, and it appears in the
chat preview mock on both the rail and the channel list.

**No chat colour follows another chat colour.** The plan had the chat header
and composer chaining through `chat_pane_*`. Flattened after review: each chat
key now names one profile key directly. That makes `color_for` a single lookup
rather than a walk, drops the cycle guard entirely, and means the editor's
"Following X" hint always names a colour you can actually see in the Profile
pages section. A model test enforces it.

**No chat page background.** `chat_page_bg` was dropped after review: chat's
panes fill the window, so the body colour is only ever visible behind the cards
on the plain chat pages (server list, settings, invites), and those keep the
profile `--page-bg` like every other page in the app — which is exactly what
they did before this feature. The `.profile-picker__search` field, which had
been the one other consumer, follows `chat_input_bg` instead; it's a text input
in the composer, and leaving it on `--page-bg` would have made it the only
profile variable inside a chat-themed control. That's a small colour change for
existing themes on one search field inside a dropdown.

**The editor toggle is a checkbox, not a radio pair.** The plan copied the
chat-identity field cards' "Use main / Set for chat" control, but at one row
per colour and 28 of them it was far too heavy. A single `[ ] Override` sitting
on the label's line says the same thing in a fraction of the space. The bulk
"set all / inherit all" buttons went the same way — dropped as clutter, easy to
add back if anyone misses them.

**Two extra chat header keys got used.** `.chat-channel-header` needed an
explicit `color`, since the channel description has no colour rule of its own
and would otherwise inherit the pane text colour, leaving `chat_topbar_text`
driving nothing visible.

### Verification

`chat_theme_test.rb` asserts computed colours in a real browser — including
that an untouched theme still renders every region exactly as it did before the
split, which is the no-migration promise checked against pixels rather than
against the constant. `chat_theme_designer_test.rb` covers the editor: the
toggle, live inherited swatches down a two-hop chain, the bulk actions, the
export skipping inherited colours, and the chat preview tab.

Full suite: 1148 unit/integration + 265 system tests green, RuboCop clean,
Brakeman clean.

---

## Resolved

All three questions raised in the first draft are settled:

1. **Background images in chat** — not wanted at all. Chat pages show flat
   `chat_page_bg`. This became [Phase 2](#phase-2-drop-background-images-from-chat),
   and it is the only change in the plan that alters how an existing theme
   renders.

2. **Chat swatches on theme cards** — no. `SWATCH_PROPERTIES` stays exactly as
   it is, profile-only. Nothing to build.

3. **Theme resolution** — unchanged. If a channel or server theme is set, the
   most relevant one wins whether or not it happens to define chat colours; a
   theme is never passed over because another one further down the chain has a
   chat palette. `ThemeHelper#active_theme_style` needs no change for this,
   because inheritance resolves **within** the chosen theme: `color_for` reads
   only its own `colors` hash and its own defaults, and never consults another
   theme. Worth stating plainly in a comment on `color_for`, since "falls back
   to the profile colours" could otherwise be misread as "falls back to the
   profile's *theme*".

---

## Possible follow-ups

Not planned, not blocking — noted only so they aren't rediscovered later:

- A chat-specific background image, if the no-images decision is ever revisited.
- Per-message-author accent colours, which several chat themes will want once
  they can control the pane behind the names.
