# Plan: Theme Background Images & Richer Import/Export

## Summary

Two related enhancements:

1. **Background image on themes** — allow uploading an image that tiles or stretches behind the page, with configurable CSS repeat/sizing options
2. **Richer import/export** — upgrade the current CSS-only import/export to a JSON format that includes colours, credit, notes, and tags (background images are excluded from import/export since they're binary blobs)

---

## Part 1: Background images

### Concept

A theme can optionally have a background image applied to the `<body>`. The user uploads an image (same constraints as avatar uploads: JPG, PNG, or WebP, max 2 MB) and configures how it should behave:

- **Repeat mode** — `repeat` (tile), `repeat-x` (tile horizontally), `repeat-y` (tile vertically), `no-repeat`
- **Size** — `auto` (natural size, for tiling), `cover` (stretch to fill viewport), `contain` (fit within viewport)
- **Position** — `center`, `top`, `top left`, `top right`, `bottom`, `bottom left`, `bottom right`, `left`, `right`
- **Attachment** — `scroll` (scrolls with content), `fixed` (stays in place as you scroll)

These four settings cover the typical use cases:

| Use case              | Size                | Repeat      | Attachment |
| --------------------- | ------------------- | ----------- | ---------- |
| Subtle tiling pattern | `auto`              | `repeat`    | `scroll`   |
| Full-screen wallpaper | `cover`             | `no-repeat` | `fixed`    |
| Top banner image      | `auto` or `contain` | `no-repeat` | `scroll`   |
| Fixed tiling texture  | `auto`              | `repeat`    | `fixed`    |

Defaults: `repeat`, `auto`, `center`, `scroll` — which gives a classic tiled background that scrolls with the page.

### Migration

```ruby
class AddBackgroundImageOptionsToThemes < ActiveRecord::Migration[8.1]
  def change
    add_column :themes, :background_repeat, :string, default: "repeat", null: false
    add_column :themes, :background_size, :string, default: "auto", null: false
    add_column :themes, :background_position, :string, default: "center", null: false
    add_column :themes, :background_attachment, :string, default: "scroll", null: false
  end
end
```

No column for the image itself — that's handled by Active Storage.

### Model changes — `Theme`

**Active Storage attachment:**

```ruby
has_one_attached :background_image
```

**Validation constants and validations:**

```ruby
BACKGROUND_IMAGE_CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze
BACKGROUND_IMAGE_MAX_SIZE = 2.megabytes

BACKGROUND_REPEAT_OPTIONS = %w[repeat repeat-x repeat-y no-repeat].freeze
BACKGROUND_SIZE_OPTIONS = %w[auto cover contain].freeze
BACKGROUND_POSITION_OPTIONS = %w[center top bottom left right].freeze
BACKGROUND_ATTACHMENT_OPTIONS = %w[scroll fixed].freeze

validate :background_image_content_type_allowed
validate :background_image_size_allowed
validates :background_repeat, inclusion: { in: BACKGROUND_REPEAT_OPTIONS }
validates :background_size, inclusion: { in: BACKGROUND_SIZE_OPTIONS }
validates :background_position, inclusion: { in: BACKGROUND_POSITION_OPTIONS }
validates :background_attachment, inclusion: { in: BACKGROUND_ATTACHMENT_OPTIONS }
```

Note on position: we keep it to single-keyword values (`center`, `top`, `bottom`, `left`, `right`) rather than compound values like `top left`. This keeps validation simple, and the five options cover the most useful placements. `center` is the sensible default for most cases (tiling benefits from it, and cover/contain centre the image nicely). Users who need `top left` can request it later, but starting with five clean options avoids overcomplicating the UI.

**Private validation methods** (following the same pattern as `HasAvatar`):

```ruby
def background_image_content_type_allowed
  return unless background_image.attached?
  unless background_image.blob.content_type.in?(BACKGROUND_IMAGE_CONTENT_TYPES)
    errors.add(:background_image, "must be a JPG/JPEG, PNG, or WebP image")
  end
end

def background_image_size_allowed
  return unless background_image.attached?
  if background_image.blob.byte_size > BACKGROUND_IMAGE_MAX_SIZE
    errors.add(:background_image, "must be 2 MB or less")
  end
end
```

**Extend `to_css_properties`** to include background image CSS. This requires the view context (for generating the Active Storage URL), so we add a separate method:

```ruby
def background_css_properties(image_url)
  return "" unless image_url.present?

  [
    "background-image: url('#{image_url}');",
    "background-repeat: #{background_repeat};",
    "background-size: #{background_size};",
    "background-position: #{background_position};",
    "background-attachment: #{background_attachment};"
  ].join(" ")
end
```

We keep this separate from `to_css_properties` because generating the image URL requires `rails_blob_url` or `rails_storage_proxy_url`, which is a controller/view concern, not a model concern.

**Duplicate support** — the `duplicate` action copies the four background option columns but does **not** copy the background image. Sharing the same Active Storage blob between two records looks tempting (same file, no extra storage), but `purge` deletes the blob and its file unconditionally — it has no reference-counting. If the user later removes the background on either theme, the other's attachment would silently point to a deleted file. The duplicate therefore starts with no background image; the user can upload one separately.

### Controller changes — `Our::ThemesController`

**Permit params:**

Add to `theme_params`:

```ruby
:background_image, :remove_background_image,
:background_repeat, :background_size, :background_position, :background_attachment
```

Validate background options are in the allowed lists (model handles this).

**Handle removal** (same pattern as avatar removal on groups):

```ruby
if params[:theme][:remove_background_image] == "1"
  @theme.background_image.purge
end
```

**Duplicate action** — copy background options and attach the blob if present:

```ruby
copy = Current.user.themes.build(
  name: "#{base_name}#{suffix}",
  colors: @theme.colors,
  tags: @theme.tags,
  credit: @theme.credit,
  credit_url: @theme.credit_url,
  notes: @theme.notes,
  shared: false,
  background_repeat: @theme.background_repeat,
  background_size: @theme.background_size,
  background_position: @theme.background_position,
  background_attachment: @theme.background_attachment
  # background_image is intentionally not copied — see note above
)
```

### ThemeHelper changes

Update `active_theme_style` to include background image properties when the resolved theme has a background image attached:

```ruby
def active_theme_style
  theme = resolve_active_theme
  return unless theme

  style = theme.to_css_properties
  if theme.background_image.attached?
    url = rails_storage_proxy_url(theme.background_image)
    style += " #{theme.background_css_properties(url)}"
  end
  style
end
```

This means refactoring the existing method slightly to extract the theme resolution into a private helper, then building the style string from both colour properties and background properties.

### View changes

**`_form.html.haml`** — add a "Background image" section (inside a `<details>` block to keep the form tidy, similar to Tags and Share sections):

```haml
%hr.form-divider
%details
  %summary Background image
  .form-group
    = form.label :background_image, "Background image (up to 2 MB)"
    = form.file_field :background_image, accept: "image/jpeg, image/png, image/webp"
    - if theme.persisted? && theme.background_image.attached?
      %p.form-hint Current background:
      = image_tag theme.background_image.variant(resize_to_limit: [200, 200]),
        class: "theme-bg-preview", width: 200, alt: "Current background image", loading: "lazy"
      %label.checkbox-label
        = check_box_tag "theme[remove_background_image]", "1", false
        Remove background image

  .form-group
    = form.label :background_repeat, "Repeat"
    = form.select :background_repeat,
      Theme::BACKGROUND_REPEAT_OPTIONS.map { |v| [v.titleize, v] },
      {}, { data: { action: "change->theme-designer#updateBackgroundPreview" } }

  .form-group
    = form.label :background_size, "Size"
    = form.select :background_size,
      Theme::BACKGROUND_SIZE_OPTIONS.map { |v| [v.titleize, v] },
      {}, { data: { action: "change->theme-designer#updateBackgroundPreview" } }

  .form-group
    = form.label :background_position, "Position"
    = form.select :background_position,
      Theme::BACKGROUND_POSITION_OPTIONS.map { |v| [v.titleize, v] },
      {}, { data: { action: "change->theme-designer#updateBackgroundPreview" } }

  .form-group
    = form.label :background_attachment, "Attachment"
    = form.select :background_attachment,
      Theme::BACKGROUND_ATTACHMENT_OPTIONS.map { |v| [v == "scroll" ? "Scroll (moves with content)" : "Fixed (stays in place)", v] },
      {}, { data: { action: "change->theme-designer#updateBackgroundPreview" } }
```

**`_preview.html.haml`** — the preview container already has `data-theme-designer-target="preview"`, and the Stimulus controller sets inline styles on it. Background image preview will be handled by the Stimulus controller reading the file input and applying a temporary object URL.

**`show.html.haml`** — the static preview needs to include background styles:

```haml
- bg_style = @theme.background_image.attached? ? " #{@theme.background_css_properties(url_for(@theme.background_image))}" : ""
.theme-preview{style: "#{@theme.to_css_properties}#{bg_style}"}
```

### Stimulus controller changes — `theme_designer_controller.js`

Add support for live-previewing the background image:

```javascript
static targets = ["colorInput", "hexInput", "preview", "cssOutput",
                   "backgroundFileInput", "backgroundRepeat",
                   "backgroundSize", "backgroundPosition",
                   "backgroundAttachment"]

// Called when user selects a background image file
previewBackgroundImage(event) {
  const file = event.target.files[0]
  if (!file) return
  if (this.bgObjectUrl) URL.revokeObjectURL(this.bgObjectUrl)
  this.bgObjectUrl = URL.createObjectURL(file)
  this.applyBackgroundToPreview()
}

updateBackgroundPreview() {
  this.applyBackgroundToPreview()
}

applyBackgroundToPreview() {
  if (!this.hasPreviewTarget) return
  const url = this.bgObjectUrl || this.previewTarget.dataset.existingBgUrl
  if (url) {
    this.previewTarget.style.backgroundImage = `url('${url}')`
  }
  if (this.hasBackgroundRepeatTarget)
    this.previewTarget.style.backgroundRepeat = this.backgroundRepeatTarget.value
  if (this.hasBackgroundSizeTarget)
    this.previewTarget.style.backgroundSize = this.backgroundSizeTarget.value
  if (this.hasBackgroundPositionTarget)
    this.previewTarget.style.backgroundPosition = this.backgroundPositionTarget.value
  if (this.hasBackgroundAttachmentTarget)
    this.previewTarget.style.backgroundAttachment = this.backgroundAttachmentTarget.value
}

disconnect() {
  if (this.bgObjectUrl) URL.revokeObjectURL(this.bgObjectUrl)
}
```

### CSS

The preview container may need a `min-height` so the background image is visible even when content is short. No new custom properties are needed — the background CSS is applied as direct properties on `<body>`, not via custom properties.

Add forced-colors consideration:

```css
@media (forced-colors: active) {
  body {
    background-image: none !important;
  }
}
```

This ensures background images don't interfere with forced-colours/high-contrast mode.

### Accessibility considerations

- Background images are decorative (they don't convey information), so no `alt` text is needed on `<body>`.
- The `forced-colors: active` media query strips background images for users in Windows High Contrast mode.
- Background images could reduce text readability. The `page_bg` colour still applies *under* the image, so if the image fails to load, the page remains readable. Users are responsible for choosing images that work with their colour scheme.
- Consider adding a note in the form: "Choose an image that doesn't reduce text readability with your chosen colours."

### Tests

**Model tests:**
- Theme with background image attached is valid
- Background image with disallowed content type is invalid
- Background image over 2 MB is invalid
- Background repeat/size/position/attachment validate inclusion
- `background_css_properties` returns correct CSS string
- `background_css_properties` returns empty string when no URL given

**Controller tests:**
- Create theme with background image
- Update theme with background image
- Remove background image via checkbox
- Duplicate theme copies background options but does not copy the background image

**System tests:**
- Upload a background image on the new theme page, see it in preview
- Edit a theme to remove its background image
- Background image appears on the public page when a theme with a background is active

---

## Part 2: Richer import/export

### Current state

**Export** (edit page): generates a `:root { --prop: #hex; ... }` CSS block in a read-only textarea. A "Copy CSS" button copies it to the clipboard.

**Import** (index page): a dialog where users paste a `:root { }` CSS block. The Stimulus controller parses `--property: #hex;` pairs and redirects to the new-theme page with colours as query params.

### Problems with the current approach

1. Only colours are exported/imported — credit, credit URL, notes, and tags are lost
2. The CSS format is fragile — users might mangle whitespace or add comments
3. No way to share theme metadata between people without manually re-entering it

### New format: JSON

Switch to a JSON-based format that includes all non-image theme data:

```json
{
  "plural_profiles_theme": 1,
  "name": "Forest Night",
  "colors": {
    "page_bg": "#0e2e24",
    "pane_bg": "#133b2f",
    "text": "#5ea389"
  },
  "tags": ["dark", "cool-colours"],
  "credit": "Dru",
  "credit_url": "https://example.com",
  "notes": "A dark green theme inspired by forests at night.",
  "background_repeat": "repeat",
  "background_size": "auto",
  "background_position": "center",
  "background_attachment": "scroll"
}
```

- `plural_profiles_theme` is a version marker (integer `1`) so we can recognise the format and evolve it later
- Background **options** are included (repeat, size, position, attachment) but the background **image** is not — binary blobs don't belong in a JSON text export
- Unknown keys are silently ignored on import, making it forward-compatible
- Colours still use the underscore-keyed model format for consistency

### Model changes

Add two methods to `Theme`:

```ruby
def to_export_hash
  {
    plural_profiles_theme: 1,
    name: name,
    colors: colors,
    tags: tags,
    credit: credit,
    credit_url: credit_url,
    notes: notes,
    background_repeat: background_repeat,
    background_size: background_size,
    background_position: background_position,
    background_attachment: background_attachment
  }.compact
end

def to_export_json
  JSON.pretty_generate(to_export_hash)
end

def self.import_attributes_from_json(json_string)
  data = JSON.parse(json_string)
  raise "Not a Plural Profiles theme" unless data["plural_profiles_theme"].is_a?(Integer)

  attrs = {}
  attrs[:name] = data["name"] if data["name"].present?
  attrs[:colors] = data["colors"].slice(*THEMEABLE_PROPERTIES.keys) if data["colors"].is_a?(Hash)
  attrs[:tags] = (data["tags"] & TAGS.keys) if data["tags"].is_a?(Array)
  attrs[:credit] = data["credit"] if data.key?("credit")
  attrs[:credit_url] = data["credit_url"] if data.key?("credit_url")
  attrs[:notes] = data["notes"] if data.key?("notes")
  attrs[:background_repeat] = data["background_repeat"] if BACKGROUND_REPEAT_OPTIONS.include?(data["background_repeat"])
  attrs[:background_size] = data["background_size"] if BACKGROUND_SIZE_OPTIONS.include?(data["background_size"])
  attrs[:background_position] = data["background_position"] if BACKGROUND_POSITION_OPTIONS.include?(data["background_position"])
  attrs[:background_attachment] = data["background_attachment"] if BACKGROUND_ATTACHMENT_OPTIONS.include?(data["background_attachment"])
  attrs
rescue JSON::ParserError
  raise "Invalid JSON"
end
```

### Controller changes

**New action** — the import now happens server-side to validate properly:

The existing flow redirects to `new` with query params. We keep that pattern but switch from CSS parsing to JSON parsing. The Stimulus controller handles the client-side parsing and redirect.

Actually, since the Stimulus controller already handles the parsing client-side, we keep the redirect-to-new approach. The Stimulus controller parses the JSON and builds query params:

```ruby
# In the `new` action, accept imported attributes:
def new
  colors = Theme::THEMEABLE_PROPERTIES.transform_values { |v| v[:default] }
  default_source = Current.user.active_theme || Theme.site_default_theme
  colors.merge!(default_source.colors) if default_source

  imported = {}
  if params[:theme].present?
    if params[:theme][:colors].present?
      imported_colors = params[:theme][:colors].to_unsafe_h
                          .transform_keys(&:to_s)
                          .slice(*Theme::THEMEABLE_PROPERTIES.keys)
      colors.merge!(imported_colors)
    end
    imported[:credit] = params[:theme][:credit] if params[:theme][:credit].present?
    imported[:credit_url] = params[:theme][:credit_url] if params[:theme][:credit_url].present?
    imported[:notes] = params[:theme][:notes] if params[:theme][:notes].present?
    imported[:tags] = Array(params[:theme][:tags]).reject(&:blank?) & Theme::TAGS.keys if params[:theme][:tags].present?
    imported[:background_repeat] = params[:theme][:background_repeat] if Theme::BACKGROUND_REPEAT_OPTIONS.include?(params[:theme][:background_repeat])
    imported[:background_size] = params[:theme][:background_size] if Theme::BACKGROUND_SIZE_OPTIONS.include?(params[:theme][:background_size])
    imported[:background_position] = params[:theme][:background_position] if Theme::BACKGROUND_POSITION_OPTIONS.include?(params[:theme][:background_position])
    imported[:background_attachment] = params[:theme][:background_attachment] if Theme::BACKGROUND_ATTACHMENT_OPTIONS.include?(params[:theme][:background_attachment])
  end

  @theme = Current.user.themes.build(
    name: imported[:name] || "New theme",
    colors: colors,
    **imported.except(:name, :colors)
  )
end
```

### Stimulus controller changes — `theme_import_controller.js`

Replace the CSS parser with a JSON parser, and add backward compatibility for pasted CSS:

```javascript
import(event) {
  event.preventDefault()
  const input = this.cssInputTarget.value.trim()

  // Try JSON first
  if (input.startsWith("{")) {
    this.importJson(input)
  } else {
    // Fallback: try legacy CSS format
    this.importCss(input)
  }
}

importJson(input) {
  try {
    const data = JSON.parse(input)
    if (!data.plural_profiles_theme) {
      this.showError("This doesn't look like a Plural Profiles theme. Make sure you paste the full JSON export.")
      return
    }

    const params = new URLSearchParams()
    if (data.name) params.append("theme[name]", data.name)
    if (data.colors && typeof data.colors === "object") {
      for (const [key, value] of Object.entries(data.colors)) {
        params.append(`theme[colors][${key}]`, value)
      }
    }
    if (Array.isArray(data.tags)) {
      data.tags.forEach(tag => params.append("theme[tags][]", tag))
    }
    if (data.credit) params.append("theme[credit]", data.credit)
    if (data.credit_url) params.append("theme[credit_url]", data.credit_url)
    if (data.notes) params.append("theme[notes]", data.notes)
    if (data.background_repeat) params.append("theme[background_repeat]", data.background_repeat)
    if (data.background_size) params.append("theme[background_size]", data.background_size)
    if (data.background_position) params.append("theme[background_position]", data.background_position)
    if (data.background_attachment) params.append("theme[background_attachment]", data.background_attachment)

    window.location.href = `${this.newUrlValue}?${params.toString()}`
  } catch (e) {
    this.showError("Invalid JSON. Make sure you paste the full export.")
  }
}

importCss(input) {
  // Existing CSS parser — kept for backward compatibility
  const colors = this.parseCss(input)
  if (Object.keys(colors).length === 0) {
    this.showError(
      "No valid theme data found. Paste either a JSON theme export or a CSS :root { } block."
    )
    return
  }
  const params = new URLSearchParams()
  for (const [key, value] of Object.entries(colors)) {
    params.append(`theme[colors][${key}]`, value)
  }
  window.location.href = `${this.newUrlValue}?${params.toString()}`
}
```

### View changes

**Export section** (`edit.html.haml`) — switch from CSS textarea to JSON:

```haml
.card{data: { controller: "clipboard" }}
  %details
    %summary Export theme
    %p.text-muted Copy this JSON to share your theme with others.
    .form-group
      %textarea.theme-designer__css-output{readonly: true, rows: 10, data: { "theme-designer-target": "jsonOutput", "clipboard-target": "source" }}= @theme.to_export_json
    %button.btn.btn--secondary{data: { action: "click->clipboard#copy" }}
      %span{data: { "clipboard-target": "label" }} Copy JSON
      %span{aria: {hidden: "true"}} ⧉
```

Also update the CSS output target in the Stimulus designer controller to reflect the JSON export, or keep both — the JSON export is static (not live-updated) while the CSS output can remain live-updated. Decision: keep both.

Actually, cleaner approach: the export textarea shows the JSON (static, generated server-side). The live CSS output stays in a separate section if desired, or is removed since the JSON export supersedes it. Let's keep it simple:

- **JSON export** (static, server-rendered) — the main export mechanism
- **Live CSS output** (Stimulus-updated) — remove it, since it's now redundant. The JSON export on the edit page is always up-to-date after saving.

If we want the export to be live-updated as colours change, the Stimulus controller could regenerate the JSON too. But that's a nice-to-have — the export only needs to be correct after saving.

**Import dialog** (`index.html.haml`) — update the placeholder and help text:

```haml
%dialog.import-dialog{...}
  %form{...}
    %h2 Import theme
    %p Paste a theme JSON export below (or a legacy CSS block).
    %textarea.import-dialog__textarea{..., placeholder: "{\n  \"plural_profiles_theme\": 1,\n  \"name\": \"My theme\",\n  \"colors\": { ... }\n}"}
    ...
```

### Updating the export in the Stimulus designer controller

To keep the export live, update the `updateCssOutput` method (renamed `updateExport`) to generate JSON:

```javascript
updateExport() {
  if (!this.hasJsonOutputTarget) return

  const colors = {}
  this.hexInputTargets.forEach(input => {
    colors[input.dataset.property] = input.value
  })

  const data = { plural_profiles_theme: 1, colors }
  // Other fields (name, tags, credit, etc.) are static — we could read them
  // from the form inputs if we want full live export, or leave them for the
  // server-rendered version after save.

  this.jsonOutputTarget.value = JSON.stringify(data, null, 2)
}
```

Decision: for simplicity, only the colours are live-updated in the export. The full JSON with all metadata is generated server-side and shown after saving. This avoids the complexity of reading every form field in JS.

### Tests

**Model tests:**
- `to_export_hash` includes all expected keys
- `to_export_json` produces valid JSON
- `import_attributes_from_json` parses valid JSON correctly
- `import_attributes_from_json` raises on invalid JSON
- `import_attributes_from_json` raises on missing version marker
- `import_attributes_from_json` ignores unknown keys
- `import_attributes_from_json` filters colours to known keys only

**Controller tests:**
- Import via JSON populates the new theme form with all attributes
- Import via legacy CSS still works (backward compatibility)

**System tests:**
- Export a theme, import it into a new theme, verify all fields match
- Import a legacy CSS block, verify colours are applied

---

## Implementation order

1. **Migration** — add background columns to themes
2. **Model** — Active Storage attachment, validations, background CSS method, export/import methods
3. **Controller** — permit new params, handle image upload/removal, update duplicate, update new action for richer import
4. **Views** — background image section in form, update export/import UI
5. **Stimulus** — background preview, JSON import, updated export
6. **CSS** — forced-colors override, preview container sizing
7. **Tests** — model, controller, system tests for both features
8. **Cleanup** — rename CSS output target, update help text

---

## Open questions

- **Max file size for background images** — 2 MB matches avatars, but backgrounds are typically larger. Should we allow up to 5 MB? (Starting with 2 MB and increasing later is safer.)
- **Should shared themes' background images be visible in the theme card?** — A small thumbnail could help users preview before activating. Could add a small preview image to the card partial.
- **Should the live preview in the designer show the background image at full scale?** — The preview container is small, so a tiled or cover image may look odd. But it's still useful for getting a sense of how the theme will look.
- **Do we want to strip EXIF data from uploaded background images?** — Active Storage variants can do this via `libvips`. Worth doing for privacy (GPS coordinates, camera info, etc.). The existing avatar uploads may also benefit from this.
