# Plan: Theme Enhancements — Credits, Notes, Shared Themes & Default Theme

## Summary

Extend the existing theme feature with four enhancements:

1. **Credit field** — a free-text "made by" field on themes (e.g. "Dru")
2. **Notes field** — a longer textarea for freeform notes about the theme
3. **Shared themes** — admin-published themes available to all users (read-only, but duplicable)
4. **Default theme** — one shared theme is marked as the site-wide default, used for logged-out visitors and logged-in users who haven't chosen a theme

### Key decisions from discussion

- **Credit field** uses a free-text "made by" string (no automatic profile link lookup) — `credit` as `string`, max 255 chars
- **Optional credit URL** allows linking to the maker's site or profile — `credit_url` as `string`, validated as a URL
- **Notes field** is a textarea — `text`, no hard limit in DB
- **Only admins can share themes** — requires a new `admin` boolean on the `users` table
- **Admins can still edit shared themes** — other users can only view and duplicate them
- **Shared themes are filterable by tags** — same tag filter UI as user themes
- **One shared theme can be marked as default** — a boolean `default` flag on the theme (enforced unique)
- **When duplicating a shared theme**, the copy inherits credit and notes, and the user can edit them freely
- **The default theme** applies to logged-out visitors and logged-in users who haven't activated a personal theme

---

## Current state

### Database

The `themes` table has: `id`, `name` (string, not null), `colors` (jsonb), `tags` (string array), `user_id` (FK), timestamps.

The `users` table has: `active_theme_id` (FK, nullable, on_delete nullify).

### Behaviour

- Themes belong to a user. Users CRUD their own themes at `our/themes`.
- A user can activate one theme; its CSS custom properties are injected into `<body style="">`.
- `ThemeHelper#active_theme_style` returns the CSS only if `authenticated? && Current.user&.active_theme`.
- Logged-out visitors see the hardcoded `:root` CSS values (the dark-green default).

---

## Phase 1: Credit and notes fields

### Migration

Add two columns to `themes`:

```ruby
add_column :themes, :credit, :string, limit: 255
add_column :themes, :notes, :text
```

### Model

- Add `credit` and `notes` to `Theme`.
- Validate `credit` length: `validates :credit, length: { maximum: 255 }`.
- No special validation on `notes` (text column, unlimited).

### Controller

- Permit `:credit` and `:notes` in `theme_params`.
- Include `credit` and `notes` when duplicating a theme.

### Views

- **`_form.html.haml`**: Add a "Made by" text input and a "Notes" textarea between the name field and the colour groups.
- **`_theme_card.html.haml`**: Show "Made by [credit]" below the theme name if present. Show notes (truncated) if present.
- **Index page**: No changes beyond what the card partial shows.

### Tests

- Model test: theme with credit and notes is valid; credit over 255 chars is invalid.
- Controller test: create/update with credit and notes; duplicate copies credit and notes.

---

## Phase 2: Admin flag on users

### Migration

```ruby
add_column :users, :admin, :boolean, default: false, null: false
```

### Model

- No association changes needed. Just the column.
- Add a helper: `def admin?; admin; end` (or rely on the boolean attribute directly).

### Usage

- Admin checks will be used in Phase 3 for sharing themes and setting the default.
- No UI for managing admins — initial admin is set via `rails console` or a seed/migration.

### Fixtures

- Set `admin: true` on one of the test user fixtures.

---

## Phase 3: Shared themes

### Concept

A shared theme is a theme that has been **published** by an admin. It becomes visible to all users on a "Shared themes" section of the themes index. Non-admin users cannot edit shared themes but can duplicate them to get a private editable copy.

### Migration

```ruby
add_column :themes, :shared, :boolean, default: false, null: false
add_index :themes, :shared, where: "shared = true", name: "index_themes_on_shared"
```

### Model changes

- `belongs_to :user` stays — shared themes still have an owning user (the admin who created them).
- Add scope: `scope :shared, -> { where(shared: true) }`.
- Add scope: `scope :personal, -> { where(shared: false) }`.
- Validation: only admins can set `shared: true` — `validate :only_admin_can_share`.

```ruby
validate :only_admin_can_share

private

def only_admin_can_share
  if shared? && !user&.admin?
    errors.add(:shared, "can only be set by admins")
  end
end
```

### Controller changes — `Our::ThemesController`

**Index action** — load shared themes for display:

```ruby
def index
  @filter_tags = Array(params[:tags]).reject(&:blank?) & Theme::TAGS.keys

  @active_theme = Current.user.active_theme
  @shared_themes = Theme.shared.order(:name)
  @shared_themes = @shared_themes.where("tags @> ARRAY[?]::varchar[]", @filter_tags) if @filter_tags.any?

  own_scope = Current.user.themes.personal
  own_scope = own_scope.where.not(id: Current.user.active_theme_id)
  own_scope = own_scope.where("tags @> ARRAY[?]::varchar[]", @filter_tags) if @filter_tags.any?
  @other_themes = own_scope.order(:name)
end
```

**Edit/update** — prevent non-admin users from editing shared themes:

```ruby
def set_theme
  @theme = Current.user.themes.find(params[:id])
end
```

This already scopes to `Current.user.themes`, so non-admins can never load a shared theme they don't own. No change needed for scoping — but within the form, admin users should see a "Shared" checkbox.

**Duplicate** — allow duplicating shared themes (even if the user doesn't own them):

```ruby
def set_theme_for_duplicate
  @theme = Theme.find(params[:id])
  # For non-shared themes, ensure it belongs to the current user
  unless @theme.shared? || @theme.user_id == Current.user.id
    raise ActiveRecord::RecordNotFound
  end
end
```

Split `set_theme` into two before_actions: `set_theme` (own themes only) and `set_theme_for_duplicate` (own + shared). Use `set_theme_for_duplicate` only for the `duplicate` action.

The duplicate action builds the copy under `Current.user` and sets `shared: false`:

```ruby
def duplicate
  copy = Current.user.themes.build(
    name: "#{base_name}#{suffix}",
    colors: @theme.colors,
    tags: @theme.tags,
    credit: @theme.credit,
    notes: @theme.notes,
    shared: false
  )
  # ...
end
```

**Permit params** — add `:shared` to permitted params, but only actually store it if the user is admin:

```ruby
def theme_params
  permitted = params.require(:theme).permit(:name, :credit, :notes, :shared, tags: [], colors: {})
  # Strip shared param if user is not admin
  permitted.delete(:shared) unless Current.user.admin?
  # ... existing tag/color filtering ...
  permitted
end
```

**Destroy** — prevent deleting a shared theme if it's the default (see Phase 4).

### View changes

**Index page (`index.html.haml`)** — three sections:

1. **Active theme** (if any) — unchanged
2. **Shared themes** — new section, shown to all users
3. **Your themes** — the user's personal (non-shared) themes

```haml
- if @shared_themes.any?
  %h2 Shared themes
  .card-list
    - @shared_themes.each do |theme|
      = render "our/themes/shared_theme_card", theme: theme
```

**New partial: `_shared_theme_card.html.haml`** — similar to `_theme_card` but:

- No "Edit" or "Delete" buttons (unless current user is admin and owns the theme)
- "Duplicate" button always shown
- "Activate" / "Deactivate" button
- Show credit, notes, tags
- Show "(default)" badge if it's the default theme

**Form (`_form.html.haml`)** — add a "Shared" checkbox, visible only to admins:

```haml
- if Current.user.admin?
  .form-group
    %label.checkbox-label
      = form.check_box :shared
      Share this theme with everyone
```

### Theme show / preview page

Non-admin users need a way to see what a shared theme actually looks like before deciding to activate or duplicate it. This is also useful for a user's own themes as a quicker read-only overview vs. loading the full editor.

**Route** — `resources :our_themes` already generates a `show` route (`GET /our/themes/:id`). No route change needed.

**Controller — new `show` action**:

```ruby
before_action :set_theme_for_show, only: %i[show]

def show
end

private

def set_theme_for_show
  # Allow viewing own themes OR any shared theme
  @theme = if Current.user.themes.exists?(params[:id])
             Current.user.themes.find(params[:id])
           else
             Theme.shared.find(params[:id])
           end
end
```

**New view: `show.html.haml`** — shares the two-column `theme-designer-container` layout with the edit view, but has no form inputs. The preview container receives the theme's CSS as a static `style` attribute rather than being driven by the Stimulus controller:

```haml
- content_for(:title) { "#{@theme.name} — Plural Profiles" }
- content_for(:container_class, "theme-designer-container")

%h1= @theme.name

.theme-designer
  .theme-designer__controls
    .card
      - if @theme.credit.present?
        %p.theme-credit Made by #{@theme.credit}
      - if @theme.notes.present?
        %p.theme-notes= @theme.notes
      - if @theme.tags.any?
        .card__tags
          - @theme.tags.each do |tag|
            %span.tag.tag--theme= Theme::TAGS[tag] || tag

      .card__actions
        - if Current.user.active_theme_id == @theme.id
          = link_to "Deactivate", deactivate_our_themes_path, data: { turbo_method: :patch }, class: "btn btn--small"
        - else
          = link_to "Activate", activate_our_theme_path(@theme), data: { turbo_method: :patch }, class: "btn btn--small"
        = link_to "Duplicate", duplicate_our_theme_path(@theme), data: { turbo_method: :post }, class: "btn btn--small btn--secondary"
        - if Current.user.admin? && @theme.shared?
          = link_to "Edit", edit_our_theme_path(@theme), class: "btn btn--small btn--secondary"

    .card
      %details
        %summary Export theme
        %p.text-muted Copy this CSS to use this theme elsewhere.
        .form-group
          %textarea.theme-designer__css-output{readonly: true, rows: 8}= @theme.to_css

  .theme-designer__preview
    .theme-preview{style: @theme.to_css_properties}
      = render "our/themes/preview"

%p= link_to "← Back to themes", our_themes_path
```

The crucial difference from the edit view: `.theme-preview{style: @theme.to_css_properties}` inlines the resolved hex values directly. No `data: { "theme-designer-target": "preview" }`, no wrapping `theme-designer` Stimulus controller. The preview renders correctly with plain CSS, JavaScript not required.

**Linking to the show page**:

- In `_shared_theme_card.html.haml`: theme name links to `our_theme_path(theme)`, and a "Preview" button is shown.
- In `_theme_card.html.haml` (own themes): theme name links to `our_theme_path(theme)` (replacing the current link to the edit page). An "Edit" button is still shown in `card__actions`.

### Tests

- Admin can create/edit a shared theme.
- Non-admin cannot set `shared: true` (validation error).
- Non-admin can see shared themes on index.
- Non-admin can duplicate a shared theme.
- Non-admin cannot edit or delete a shared theme.
- Duplicated shared theme belongs to current user with `shared: false`.
- Any logged-in user can visit the show page for a shared theme.
- A user can visit the show page for their own theme.
- A user cannot visit the show page for another user's personal theme (→ 404).

---

## Phase 4: Default theme

### Concept

Exactly one shared theme can be marked as the **default**. This theme is used:

- For **logged-out visitors** (currently they see only the hardcoded CSS)
- For **logged-in users who have not activated a theme** (`active_theme_id` is nil)

### Migration

```ruby
add_column :themes, :site_default, :boolean, default: false, null: false
add_index :themes, :site_default, unique: true, where: "site_default = true", name: "index_themes_on_site_default_unique"
```

### Model changes

- Validation: `site_default` can only be true on shared themes.

```ruby
validate :site_default_must_be_shared

def site_default_must_be_shared
  if site_default? && !shared?
    errors.add(:site_default, "can only be set on shared themes")
  end
end
```

- Before save callback: if setting `site_default: true`, clear it on all other themes (within a transaction).

```ruby
before_save :clear_other_defaults, if: -> { site_default? && site_default_changed? }

def clear_other_defaults
  Theme.where(site_default: true).where.not(id: id).update_all(site_default: false)
end
```

- Class method to look up the default:

```ruby
def self.site_default_theme
  find_by(site_default: true)
end
```

### ThemeHelper changes

Update `active_theme_style` to fall back to the site default:

```ruby
module ThemeHelper
  def active_theme_style
    theme = if authenticated? && Current.user&.active_theme
              Current.user.active_theme
            else
              Theme.site_default_theme
            end
    theme&.to_css_properties
  end
end
```

Consider **caching** the default theme lookup to avoid a DB query on every request for logged-out visitors. Options:

- **Rails.cache** with a short TTL (e.g. 5 minutes) — simplest
- **Class-level memoization** cleared on theme save — riskier with multiple processes

Recommendation: use `Rails.cache.fetch("site_default_theme", expires_in: 5.minutes)` pattern.

```ruby
def self.site_default_theme
  Rails.cache.fetch("site_default_theme", expires_in: 5.minutes) do
    find_by(site_default: true)
  end
end
```

Bust the cache when a theme's `site_default` changes:

```ruby
after_save :bust_default_theme_cache, if: -> { saved_change_to_site_default? }
after_destroy :bust_default_theme_cache, if: :site_default?

def bust_default_theme_cache
  Rails.cache.delete("site_default_theme")
end
```

### Controller changes

**Admin action to set/unset default** — add a `set_default` member action:

```ruby
# routes
member do
  patch :activate
  patch :set_default
  post :duplicate
end

# controller
def set_default
  unless Current.user.admin?
    redirect_to our_themes_path, alert: "Only admins can set the default theme."
    return
  end
  @theme.update!(site_default: !@theme.site_default?)
  if @theme.site_default?
    redirect_to our_themes_path, notice: "'#{@theme.name}' is now the default theme."
  else
    redirect_to our_themes_path, notice: "'#{@theme.name}' is no longer the default theme."
  end
end
```

**Destroy** — prevent destroying the current default theme (or automatically unset it):

```ruby
def destroy
  if @theme.site_default?
    redirect_to our_themes_path, alert: "Cannot delete the default theme. Remove its default status first."
    return
  end
  # ... existing destroy logic
end
```

### View changes

**Shared theme card** — show a "(default)" badge on the card. If admin, show a "Set as default" / "Remove default" button.

**Form** — if admin and theme is shared, show a "Site default" checkbox.

**`ThemeHelper`** — already updated above; no layout changes needed since `<body style="">` already receives the CSS string.

### Deactivate wording

When a user clicks "Deactivate" on their active theme, the flash should say "Switched to site default theme" (instead of "Switched back to default theme") to clarify what's happening.

### Tests

- Setting `site_default: true` clears it on other themes (uniqueness).
- `site_default` can only be set on shared themes.
- Non-admin cannot set `site_default`.
- Logged-out visitors see the default theme's CSS.
- Logged-in user without an active theme sees the default theme's CSS.
- Logged-in user with an active theme sees their own theme's CSS (not the default).
- Deleting the default theme is prevented.
- Cache is busted when default changes.

---

## Migration order

All changes can be done in two migrations (or one, but two is cleaner):

1. **`AddThemeEnhancements`** — adds `credit`, `notes`, `shared`, `site_default` to `themes`
2. **`AddAdminToUsers`** — adds `admin` boolean to `users`

These have no dependencies on each other and can be run in either order.

---

## Implementation order

| Step | What                                                                 | Depends on   |
| ---- | -------------------------------------------------------------------- | ------------ |
| 1    | Migration: credit + notes on themes                                  | —            |
| 2    | Model + controller + views for credit & notes                        | Step 1       |
| 3    | Tests for credit & notes                                             | Step 2       |
| 4    | Migration: admin on users                                            | —            |
| 5    | Migration: shared + site_default on themes                           | —            |
| 6    | Model changes for shared themes                                      | Steps 4, 5   |
| 7    | Controller changes for shared themes                                 | Step 6       |
| 8    | Views for shared themes (index sections, shared card, form checkbox) | Step 7       |
| 9    | Theme show/preview page (controller action + view)                   | Step 7       |
| 10   | Tests for shared themes + preview page                               | Steps 8, 9   |
| 11   | Model + helper changes for default theme                             | Step 6       |
| 12   | Controller + view changes for default theme                          | Step 11      |
| 13   | Tests for default theme                                              | Step 12      |
| 14   | System tests for full flow                                           | Steps 10, 13 |

---

## Open questions / future considerations

- **Admin UI**: Currently there's no admin section. The admin flag is just a column; admin-specific actions are gated by `Current.user.admin?` checks in controllers. A dedicated admin namespace could come later.
- **Theme preview on public pages**: Currently shared themes are only shown on the `our/themes` index. A future enhancement could let logged-out visitors browse shared themes.
- **Credit as a link**: The credit field is plain text for now. Could add an optional URL field later if theme authors want to link to their sites.
- **Notes rendering**: Notes are shown as plain text. Markdown rendering could be added later.
- **Theme count limits**: No limit on how many themes a user can create. Could add a cap if needed.
