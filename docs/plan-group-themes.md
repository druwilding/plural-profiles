# Plan: Per-Group Public Themes

## Summary

Allow each group to have an optional **theme** that is applied on its public page (and on profiles viewed within that group's context). The group owner picks from a dropdown of their personal themes and shared themes. Visitors see the group's theme instead of the site default. A **theme credit footer** shows the theme name and attribution. Logged-in users can toggle a preference to **always use their own theme**, overriding group themes for accessibility.

### Key decisions from discussion

- **Group theme applies to profiles within that group** — viewing `/groups/:uuid/profiles/:uuid` uses the group's theme, not the site default
- **Personal themes become visually public** — assigning a personal (non-shared) theme to a group exposes its colours to visitors, though the theme record itself stays private
- **Override is a simple user preference** — a boolean toggle on the account page: "Always use my theme on public pages"
- **Theme credit footer** shows the theme name and "Made by [credit]" (linked to `credit_url` if present); hidden if no theme is assigned or if the theme has no name/credit
- **Dropdown groups personal and shared themes** — an `<optgroup>` select with "Our themes" and "Shared themes" sections, plus a blank "None" option at the top
- **No theme on profiles outside a group context** — standalone profile pages (`/profiles/:uuid`) are unaffected; they use the visitor's theme or site default as before

---

## Current state

### Database

- `groups`: `id`, `name`, `description`, `uuid`, `avatar` (Active Storage), `avatar_alt_text`, `labels` (jsonb), `user_id`, timestamps — **no theme column**
- `themes`: `id`, `name`, `colors` (jsonb), `tags` (string array), `shared`, `site_default`, `credit`, `credit_url`, `notes`, `user_id`, timestamps
- `users`: `id`, `email_address`, `password_digest`, `admin`, `active_theme_id` (FK → themes), timestamps — **no override preference**

### Behaviour

- `ThemeHelper#active_theme_style` returns CSS properties from the logged-in user's `active_theme`, falling back to `Theme.site_default_theme`. This is applied via `%body{style: active_theme_style}` in the application layout.
- Public group pages (`GroupsController#show`, `GroupProfilesController#show`) do not consider any group-specific theme.
- The dropdown for activating a theme exists only on the themes management page (`our/themes`).

---

## Phase 1: Data layer — group theme + user override preference

### Migration

```ruby
class AddThemeToGroupsAndOverrideToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :groups, :theme, foreign_key: { on_delete: :nullify }, null: true
    add_column :users, :override_group_themes, :boolean, default: false, null: false
  end
end
```

The `on_delete: :nullify` ensures that if a theme is deleted, groups using it gracefully fall back to no theme rather than breaking.

### Model changes

**Group**:

```ruby
class Group < ApplicationRecord
  belongs_to :theme, optional: true
  # ...
end
```

No ownership validation on the theme — any theme the user can see (their own or shared) is valid. The controller will enforce the allowed set.

**User**:

No model changes beyond the new column. `override_group_themes` is a simple boolean attribute.

### Tests

- Unit test: group with a theme association is valid; group without a theme is valid.
- Unit test: deleting a theme nullifies the group's `theme_id`.

---

## Phase 2: Group form — theme dropdown

### Controller changes — `Our::GroupsController`

**`edit` / `new` actions** — load themes for the dropdown:

```ruby
def new
  @group = Current.user.groups.build
  load_theme_options
end

def edit
  load_theme_options
end

private

def load_theme_options
  @personal_themes = Current.user.themes.order(:name)
  @shared_themes = Theme.shared.order(:name)
end
```

**`group_params`** — permit `:theme_id`:

```ruby
def group_params
  params.require(:group).permit(:name, :description, :avatar, :avatar_alt_text, :created_at, :labels_text, :theme_id)
end
```

**`create` / `update`** — validate the chosen theme is allowed:

```ruby
before_action :validate_theme_choice, only: %i[create update]

def validate_theme_choice
  theme_id = params.dig(:group, :theme_id)
  return if theme_id.blank?

  allowed_ids = Current.user.theme_ids + Theme.shared.pluck(:id)
  unless allowed_ids.include?(theme_id.to_i)
    @group ||= Current.user.groups.build
    @group.errors.add(:theme, "is not available")
    load_theme_options
    render :edit, status: :unprocessable_entity and return
  end
end
```

Also call `load_theme_options` in the `create` and `update` failure paths (when re-rendering the form).

### View changes — `_form.html.haml`

Add a theme selector between the labels field and the created_at field:

```haml
.form-group
  = form.label :theme_id, "Public theme"
  = form.select :theme_id, grouped_theme_options(@personal_themes, @shared_themes), { include_blank: "None (use default)", selected: group.theme_id }, {}
  %p.form-hint Visitors to this group's public page will see this theme. Leave blank for the site default.
```

### Helper — `GroupsHelper` or `Our::GroupsHelper`

Add a helper to build the grouped options:

```ruby
module Our::GroupsHelper
  def grouped_theme_options(personal, shared)
    groups = []
    groups << ["Our themes", personal.map { |t| [t.name, t.id] }] if personal.any?
    groups << ["Shared themes", shared.map { |t| [t.name, t.id] }] if shared.any?
    groups
  end
end
```

Use `grouped_options_for_select` in the view:

```haml
= form.select :theme_id, grouped_options_for_select(grouped_theme_options(@personal_themes, @shared_themes), group.theme_id), { include_blank: "None (use default)" }, {}
```

### Tests

- Controller test: creating a group with a personal theme_id succeeds.
- Controller test: creating a group with a shared theme_id succeeds.
- Controller test: creating a group with another user's non-shared theme_id is rejected.
- Controller test: updating a group's theme_id works.
- Controller test: clearing theme_id (setting to blank) works.
- System test: the theme dropdown appears on the edit page with grouped options.

---

## Phase 3: Apply group theme on public pages

### ThemeHelper changes

Rework `active_theme_style` to accept a group context and respect the user override:

```ruby
module ThemeHelper
  def active_theme_style
    # Logged-in user who wants their own theme everywhere
    if authenticated? && Current.user&.active_theme
      if Current.user.override_group_themes? || !@group_theme
        return Current.user.active_theme.to_css_properties
      end
    end

    # Group theme (set by controller via @group_theme)
    if @group_theme
      return @group_theme.to_css_properties
    end

    # Fallback: site default
    Theme.site_default_theme&.to_css_properties
  end
end
```

The logic:
1. If the user is logged in, has an active theme, AND has `override_group_themes` enabled → use their theme (accessibility override).
2. If the user is logged in, has an active theme, but has NOT enabled override AND there's a group theme → use the group theme.
3. If there's a group theme (unauthenticated visitor) → use it.
4. Otherwise → site default.

Edge case: logged-in user with no active theme → group theme applies (no override possible without a personal theme).

### Controller changes

**`GroupsController#show`** and **`GroupsController#panel`**:

```ruby
def show
  @group = Group.find_by!(uuid: params[:uuid])
  @group_theme = @group.theme
  # ... existing code ...
end
```

**`GroupProfilesController#show`** and **`GroupProfilesController#panel`**:

```ruby
def show
  @group = Group.find_by!(uuid: params[:group_uuid])
  @group_theme = @group.theme
  # ... existing code ...
end
```

The `@group_theme` instance variable is what `ThemeHelper` reads. Setting it in the controller keeps the helper simple and testable.

### Tests

- Controller test: public group page with a theme assigns `@group_theme`.
- Controller test: public group page without a theme has nil `@group_theme`.
- Helper test: `active_theme_style` returns group theme CSS when `@group_theme` is set and user is unauthenticated.
- Helper test: `active_theme_style` returns user's theme when `override_group_themes` is true.
- Helper test: `active_theme_style` returns group theme when user is logged in but override is false.
- Helper test: `active_theme_style` returns group theme when user is logged in with no active theme (override irrelevant).
- System test: visiting a group with a theme shows that theme's colours.

---

## Phase 4: Theme credit footer on public pages

### View changes

Add a theme credit partial that's rendered at the bottom of public group pages:

**`app/views/groups/_theme_credit.html.haml`**:

```haml
- if group.theme.present?
  .theme-credit
    %span.theme-credit__name
      Theme:
      = group.theme.name
    - if group.theme.credit.present?
      %span.theme-credit__by
        — Made by
        - if group.theme.credit_url.present?
          = link_to group.theme.credit, group.theme.credit_url, target: "_blank", rel: "noopener noreferrer"
        - else
          = group.theme.credit
```

**`app/views/groups/show.html.haml`** — render the partial at the bottom of the page (after the explorer and after the simple card fallback):

```haml
= render "groups/theme_credit", group: @group
```

**`app/views/groups/group_content_fallback`** — also include it in the no-JS fallback section, or render it once at the very end of the show template outside both branches.

**`app/views/group_profiles/show.html.haml`** — if a profile-within-group page has its own template, add the credit there too. If it shares the groups layout, the credit is already present.

### CSS

```css
.theme-credit {
  text-align: center;
  padding: 1rem;
  margin-top: 2rem;
  font-size: 0.85rem;
  color: color-mix(in srgb, var(--text) 60%, transparent);
}

.theme-credit__name {
  font-weight: 600;
}

.theme-credit__by {
  margin-left: 0.25em;
}

.theme-credit a {
  color: var(--link);
}

@media (forced-colors: active) {
  .theme-credit {
    color: CanvasText;
  }
  .theme-credit a {
    color: LinkText;
  }
}
```

### Tests

- System test: public group page with a themed group shows "Theme: [name]" footer.
- System test: theme credit shows "Made by [credit]" when credit is present.
- System test: theme credit links to credit_url when present.
- System test: no theme credit shown when group has no theme.

---

## Phase 5: User preference — override group themes

### Account controller changes — `Our::AccountController`

Add an `update_preferences` action:

```ruby
def update_preferences
  Current.user.update!(override_group_themes: params[:override_group_themes] == "1")
  redirect_to our_account_path, notice: "Preferences updated."
end
```

### Routes

```ruby
resource :our_account, path: "our/account", controller: "our/account", only: %i[show] do
  patch :update_password
  patch :update_email
  delete :cancel_email_change
  patch :update_preferences
end
```

### View changes — `app/views/our/account/show.html.haml`

Add a new card section for display preferences:

```haml
.card
  %h2 Display preferences
  = form_with url: update_preferences_our_account_path, method: :patch do |form|
    .form-group
      %label.checkbox-label
        = check_box_tag :override_group_themes, "1", Current.user.override_group_themes
        Always use our theme on public pages
      %p.form-hint
        When enabled, group pages will always display in your active theme
        instead of the group's chosen theme. Useful for accessibility.

    .form-group
      = form.submit "Save preferences"
```

### Tests

- Controller test: `update_preferences` sets `override_group_themes` to true.
- Controller test: `update_preferences` sets `override_group_themes` to false when unchecked.
- System test: toggling the preference and visiting a themed group page shows the user's own theme.
- System test: with override off, visiting a themed group page shows the group's theme.

---

## Phase 6: Eager-loading and N+1 prevention

### Considerations

The group's theme is loaded once per request (via `@group.theme`), so there's no N+1 concern for the public page itself. However:

- **Home page / index pages**: if groups are listed with their theme name, add `.includes(:theme)` to the query.
- **Our::GroupsController#index**: if showing theme names in the group list, preload themes.

For the initial implementation, the theme is only relevant on the `show` action, so no eager-loading changes are needed. Add `.includes(:theme)` later if theme info appears on index/list pages.

---

## Implementation order

| Phase | What                                                              | Depends on       |
| ----- | ----------------------------------------------------------------- | ---------------- |
| 1     | Migration: `theme_id` on groups, `override_group_themes` on users | —                |
| 2     | Group form: theme dropdown in edit/new                            | Phase 1          |
| 3     | Apply group theme on public pages (ThemeHelper + controllers)     | Phase 1          |
| 4     | Theme credit footer on public pages                               | Phase 3          |
| 5     | User override preference (account page toggle)                    | Phase 1, Phase 3 |
| 6     | Eager-loading review                                              | Phase 3          |

Phases 2, 3, and 5 can be developed in parallel after Phase 1. Phase 4 depends on Phase 3 (the theme must actually be applied before showing credit for it).

---

## Files to create or modify

### New files
- Migration: `db/migrate/XXXXXX_add_theme_to_groups_and_override_to_users.rb`
- Partial: `app/views/groups/_theme_credit.html.haml`

### Modified files
- `app/models/group.rb` — add `belongs_to :theme`
- `app/controllers/our/groups_controller.rb` — permit `theme_id`, load theme options, validate choice
- `app/views/our/groups/_form.html.haml` — add theme dropdown
- `app/helpers/theme_helper.rb` — rework `active_theme_style` for group/override logic
- `app/controllers/groups_controller.rb` — set `@group_theme`
- `app/controllers/group_profiles_controller.rb` — set `@group_theme`
- `app/views/groups/show.html.haml` — render theme credit
- `app/controllers/our/account_controller.rb` — add `update_preferences`
- `app/views/our/account/show.html.haml` — add override toggle
- `config/routes.rb` — add `update_preferences` route
- `app/assets/stylesheets/application.css` — add `.theme-credit` styles
- `app/helpers/our/groups_helper.rb` (or create) — `grouped_theme_options` helper

### Test files
- `test/models/group_test.rb` — theme association tests
- `test/controllers/our/groups_controller_test.rb` — theme_id param tests
- `test/helpers/theme_helper_test.rb` (or create) — override/group theme logic tests
- `test/controllers/groups_controller_test.rb` — `@group_theme` assignment tests
- `test/controllers/group_profiles_controller_test.rb` — `@group_theme` assignment tests
- `test/controllers/our/account_controller_test.rb` — preferences tests
- `test/system/` — theme display and override system tests

### Fixtures
- `test/fixtures/themes.yml` — may need a shared theme fixture if not already present
- `test/fixtures/groups.yml` — add `theme_id` to at least one group fixture
