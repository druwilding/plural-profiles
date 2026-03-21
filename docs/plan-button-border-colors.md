# Plan: Button Border Colours

## Summary

Add independent **border colour** properties to all three button types (primary, secondary, danger). Currently the border colour is hard-wired to the text colour in every case. This change lets theme creators set a distinct border colour per button type without affecting the text.

## Decisions

| Question             | Decision                                                                                                                                      |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| New properties       | `primary_button_border`, `secondary_button_border`, `danger_button_border`                                                                    |
| CSS variable names   | `--primary-button-border`, `--secondary-button-border`, `--danger-button-border`                                                              |
| `:root` defaults     | Reference the text vars (e.g. `--primary-button-border: var(--primary-button-text)`) so un-themed pages auto-follow text colour               |
| Model defaults (hex) | Same hex values as the corresponding text defaults: `#58cc9d`, `#58cc9d`, `#e6c4cf`                                                           |
| Scope                | All button-like elements: `.btn`, `.btn--secondary`, `.btn--outline`, `.btn--danger`, `input[type="file"]::file-selector-button`              |
| Migration strategy   | Always write — every existing theme gets an explicit border colour (copied from its stored text colour, or the model default hex if unstored) |

## Current state

### CSS `:root`

```css
--primary-button-bg: #11694a;
--primary-button-text: #58cc9d;
--secondary-button-bg: var(--pane-bg);
--secondary-button-text: var(--primary-button-text);
--danger-button-bg: #a81d49;
--danger-button-text: #e6c4cf;
```

No `--*-button-border` variables exist yet.

### Button border rules (all use text colour)

| Selector                                   | Current rule                                     |
| ------------------------------------------ | ------------------------------------------------ |
| `input[type="submit"], button, .btn`       | `border: 1px solid var(--primary-button-text)`   |
| `.btn--secondary`                          | `border: 1px solid var(--secondary-button-text)` |
| `.btn--outline`                            | `border: 1px solid var(--secondary-button-text)` |
| `.btn--danger`                             | `border: 1px solid var(--danger-button-text)`    |
| `input[type="file"]::file-selector-button` | `border: 1px solid var(--primary-button-text)`   |

### Theme model

`THEMEABLE_PROPERTIES` has `primary_button_bg`, `primary_button_text`, `secondary_button_bg`, `secondary_button_text`, `danger_button_bg`, `danger_button_text` — no border entries.

---

## Step 1 — Migration: add border colours to existing themes

A data migration that iterates all themes and writes the three new border colour keys into each theme's `colors` jsonb hash. For each button type, the value is copied from the stored text colour if present, otherwise the model default hex is used.

```ruby
class AddButtonBorderColorsToThemes < ActiveRecord::Migration[8.1]
  BORDER_DEFAULTS = {
    "primary_button_border"   => { from: "primary_button_text",   fallback: "#58cc9d" },
    "secondary_button_border" => { from: "secondary_button_text", fallback: "#58cc9d" },
    "danger_button_border"    => { from: "danger_button_text",    fallback: "#e6c4cf" }
  }.freeze

  def up
    Theme.find_each do |theme|
      colors = theme.colors || {}
      BORDER_DEFAULTS.each do |border_key, config|
        colors[border_key] = colors[config[:from]] || config[:fallback]
      end
      theme.update_column(:colors, colors)
    end
  end

  def down
    Theme.find_each do |theme|
      colors = theme.colors || {}
      BORDER_DEFAULTS.each_key { |key| colors.delete(key) }
      theme.update_column(:colors, colors)
    end
  end
end
```

This uses `update_column` to bypass validations and callbacks, ensuring it's safe to run on any state. The `down` method strips the keys cleanly.

---

## Step 2 — Model: add border entries to `THEMEABLE_PROPERTIES`

Add three entries to the `THEMEABLE_PROPERTIES` hash in `Theme`, placed immediately after their corresponding text entries in the `:buttons` group:

```ruby
"primary_button_border"    => { label: "Main button border",    default: "#58cc9d", group: :buttons },
"secondary_button_border"  => { label: "Default button border", default: "#58cc9d", group: :buttons },
"danger_button_border"     => { label: "Danger button border",  default: "#e6c4cf", group: :buttons },
```

No other model changes are needed — `color_for`, `to_css_properties`, `to_css`, validation, and the form/preview all derive from this hash automatically.

---

## Step 3 — CSS: add variables and update border rules

### 3a — Add new custom properties to `:root`

Insert after the existing button text variables:

```css
--primary-button-border: var(--primary-button-text);
--secondary-button-border: var(--secondary-button-text);
--danger-button-border: var(--danger-button-text);
```

By referencing the text vars, the default appearance is identical to today — no visual change unless a theme explicitly overrides the border.

### 3b — Update border declarations

| Selector                                   | Before                                           | After                                              |
| ------------------------------------------ | ------------------------------------------------ | -------------------------------------------------- |
| `input[type="submit"], button, .btn`       | `border: 1px solid var(--primary-button-text)`   | `border: 1px solid var(--primary-button-border)`   |
| `.btn--secondary`                          | `border: 1px solid var(--secondary-button-text)` | `border: 1px solid var(--secondary-button-border)` |
| `.btn--outline`                            | `border: 1px solid var(--secondary-button-text)` | `border: 1px solid var(--secondary-button-border)` |
| `.btn--danger`                             | `border: 1px solid var(--danger-button-text)`    | `border: 1px solid var(--danger-button-border)`    |
| `input[type="file"]::file-selector-button` | `border: 1px solid var(--primary-button-text)`   | `border: 1px solid var(--primary-button-border)`   |

---

## Step 4 — Preview and theme designer

The preview partial (`_preview.html.haml`) already renders all three button types — no changes needed there.

The theme designer Stimulus controller (`theme_designer_controller.js`) is fully generic: it reads the `data-property` attribute from each colour input and applies it to the preview via `style.setProperty`. The form partial (`_form.html.haml`) iterates `THEMEABLE_PROPERTIES` to generate inputs. Since step 2 adds the new properties to that hash, the form will automatically generate colour pickers for the three border colours, and the designer controller will apply them to the preview live.

**No JS or HAML changes needed.**

---

## Step 5 — CSS import controller

The `theme_import_controller.js` parses `--custom-property: #hex` pairs and converts hyphens to underscores. The new `--primary-button-border` etc. will be parsed as `primary_button_border` automatically — matching the model keys.

**No JS changes needed.**

---

## Step 6 — Tests

### Model tests

- Theme with valid `primary_button_border`, `secondary_button_border`, `danger_button_border` hex values is valid.
- `color_for("primary_button_border")` returns the stored value when set, the default hex when unset.
- `to_css_properties` includes `--primary-button-border`, `--secondary-button-border`, `--danger-button-border`.
- `to_css` output includes the three new properties.

### Controller tests

- Create a theme with border colours → they are persisted.
- Update a theme's border colours → they are changed.
- Duplicate a theme → border colours are copied.

### System tests

- In the theme editor, the three new colour pickers appear in the "Buttons" group.
- Changing a border colour updates the preview buttons' borders in real time.

---

## Regression safety

The combination of:

1. `:root` vars defaulting to `var(--*-button-text)` (no visual change without a theme)
2. The data migration copying text → border for every existing theme

ensures **zero visual regression** — every themed and un-themed page will look identical to today after deployment.
