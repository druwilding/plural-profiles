# Copilot Instructions — Plural Profiles

These instructions are automatically loaded by GitHub Copilot in VS Code. They apply to every conversation in this project.

## ⚠️ Language sensitivity — CRITICAL

**Never use the word "system" when referring to plural people.** Not in views, not in code, not in comments, not in variable names, not in test names. It is dehumanising. Use "collective", "group", "household", or simply "account" depending on context.

Plurality is the experience of more than one person sharing a body. This app exists to help plural folk present themselves. Treat this with respect.

## Project overview

A Rails web app for plural folk to create and share multiple profiles. Each account can have profiles (name, pronouns, description, avatar) and groups. Profiles and groups get unique shareable UUID URLs. Visitors can only see what they're linked to — there's no way to browse from one profile to discover others.

## Tech stack

| Layer | Technology |
|---|---|
| Language | Ruby 3.3.10 |
| Framework | Rails 8.1.2 |
| Database | PostgreSQL 16 |
| Templates | **HAML** (via `haml-rails`) — not ERB |
| Assets | Propshaft pipeline, hand-written CSS |
| JS | Importmap + Hotwire (Turbo & Stimulus) |
| Uploads | Active Storage (local dev, S3 in production) |
| Auth | Rails 8 built-in authentication generator (has_secure_password) |
| Server | Puma |
| Hosting | Scalingo |

## Code conventions

### Views — HAML only
All views use `.html.haml`. Never generate ERB templates. Use HAML syntax for everything including partials and layouts.

### CSS — hand-written, no frameworks
The app uses a single `application.css` file with CSS custom properties (see `:root` block). There is no Tailwind, Bootstrap, or any CSS framework. All styling is hand-written.

Key custom properties: `--page-bg`, `--pane-bg`, `--pane-border`, `--text`, `--link`, `--heading`, `--primary-button-bg`, `--primary-button-text`, `--secondary-button-text`, `--danger-button-bg`, `--danger-button-text`, `--input-label`, `--input-bg`, `--input-border`, `--spoiler`, `--notice-bg`, `--notice-border`, `--notice-text`, `--alert-bg`, `--alert-border`, `--alert-text`, `--warning-bg`, `--warning-border`, `--warning-text`, `--tree-guide`, `--avatar-placeholder-border`.

**All colours must reference these root variables** — never use hard-coded hex values, `rgb()`, or `rgba()` outside the `:root` block. For tints and transparencies, use `color-mix(in srgb, var(--some-var) X%, transparent)` or `color-mix(in srgb, var(--some-var) X%, var(--other-var))`.

Always consider `@media (forced-colors: active)` for accessibility when adding interactive or visual components. Use system colours (`Canvas`, `CanvasText`, `Highlight`, `HighlightText`, `ButtonText`, `ButtonFace`) in forced-colors mode.

### Naming conventions
- CSS: BEM-ish (e.g. `.card`, `.card__header`, `.card__actions`, `.btn`, `.btn--outline`, `.avatar--small`)
- Routes: authenticated actions are namespaced under `our/` (e.g. `Our::ProfilesController`, `Our::GroupsController`)
- Shared-link controllers are at the root namespace (`ProfilesController`, `GroupsController`)
- Models use singular names; join tables use both model names (`GroupGroup`, `GroupProfile`)

### Testing
- **Unit and controller tests:** `bin/rails test` — standard Minitest with fixtures
- **System tests:** `bin/rails test:system` — Capybara + Selenium + headless Chrome
- System test base class is in `test/application_system_test_case.rb`
- Debug helpers:
  - `HEADLESS=false bin/rails test:system` — run with visible Chrome browser
  - `SLOWMO=true bin/rails test:system` — add 0.5s delays between actions
  - `SLOWMO=2 bin/rails test:system` — custom delay in seconds
  - Combine: `HEADLESS=false SLOWMO=1 bin/rails test:system`
- Fixtures are in `test/fixtures/` — prefer fixtures over factory-based approaches
- CI runs four jobs: `scan_ruby` (brakeman + bundler-audit), `scan_js` (importmap audit), `lint` (rubocop), `test` + `system-test`

### Linting
- RuboCop with Rails Omakase style guide (`rubocop-rails-omakase`)
- Run with `bin/rubocop`, auto-fix with `bin/rubocop -a`

### JavaScript
- Use Importmap for JS dependencies (no npm/yarn/node for the Rails app)
- Stimulus controllers go in `app/javascript/controllers/`
- Turbo is used for page navigation and form submissions — be mindful of Turbo Drive caching when writing system tests (page snapshots can show stale state)

## Data model

```
User
 ├── has_many Profiles (name, pronouns, description, avatar, uuid)
 ├── has_many Groups (name, description, avatar, uuid)
 └── has_many Sessions

Profile ←→ Group  (many-to-many via GroupProfile)
Group   ←→ Group  (many-to-many via GroupGroup)
```

### Group nesting & visibility

`GroupGroup` is a simple join table linking parent and child groups (just `parent_group_id`, `child_group_id`, and timestamps). All edges are fully recursive — the CTE follows every link.

Visibility is controlled by `InclusionOverride` records. Each override hides a specific group or profile within a particular root group's tree, scoped by the **traversal path** (an array of group IDs from root to the item's container). This allows the same item to be hidden along one path but visible along another when a group appears at multiple points in a diamond-shaped tree.

Key methods in `Group`:
- `reachable_group_ids` / `descendant_group_ids` — recursive CTE returning all group IDs in the tree (aliased, identical)
- `all_profiles` — all profiles reachable from this group, respecting path-scoped overrides
- `descendant_tree` — nested hash structure for sidebar tree rendering, applying overrides
- `descendant_sections` — depth-first flat list of groups with their direct profiles for page sections
- `management_tree` — full unfiltered tree with `hidden` / `cascade_hidden` flags for the manage-groups UI
- `overrides_index` — loads all `InclusionOverride` records for a root group into a Set of `[path, target_type, target_id]` tuples for O(1) lookups during traversal

### UUIDs
All profiles and groups use `SecureRandom.uuid` (stored as `uuid` column) for shareable URLs. Internal IDs are standard Rails auto-increment integers used only in authenticated routes.

## File structure highlights

```
app/controllers/our/   — authenticated (profiles, groups CRUD)
app/controllers/       — shareable links (profiles, groups, group_profiles show)
app/views/our/         — management views (HAML)
app/views/             — shareable-link views (HAML)
app/models/            — User, Profile, Group, GroupGroup, GroupProfile
app/assets/stylesheets/application.css — single CSS file, hand-written
test/models/           — unit tests
test/controllers/      — controller tests
test/system/           — Capybara system tests
test/fixtures/         — test data
```

## Common pitfalls

1. **Turbo caching in system tests**: After a Turbo-driven redirect, the cached page snapshot may briefly show stale state. Use `assert_current_path` or wait for specific content rather than immediately checking form state after navigation.

2. **Avatar placeholder sizing**: `.avatar--placeholder` has `min-width: 64px` / `min-height: 64px`. When using `.avatar--small` (40px), you must also set `min-width: 40px` / `min-height: 40px` on the compound selector to override.

3. **Circular group references**: The `GroupGroup` model validates against circular references (a group can't be its own ancestor). Keep this in mind when creating test fixtures.

4. **Path-scoped overrides**: Inclusion overrides use a `path` (jsonb array of group IDs) to scope visibility to a specific traversal route through the tree. The same group or profile can be hidden along one path but visible along another. Empty path `[]` means the target is directly on the root group.

## Deployment

- Hosted on **Scalingo** (Heroku-like PaaS)
- `Procfile` handles web process and post-deploy migration
- `.buildpacks` uses APT + Ruby buildpacks (APT installs libvips for image processing)
- S3-compatible storage for Active Storage in production
- Environment variables: `DATABASE_URL`, `SECRET_KEY_BASE`, `APP_HOST`, `ACTIVE_STORAGE_SERVICE`, `S3_*`
