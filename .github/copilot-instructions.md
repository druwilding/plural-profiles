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

Key custom properties: `--bg`, `--text`, `--link`, `--heading`, `--bg-contrast`, `--error`, `--success`, `--warning`, `--input-bg`, `--input-border`, `--spoiler`, `--tree-guide`, `--placeholder-border`.

Always consider `@media (forced-colors: active)` for accessibility when adding interactive or visual components. Use system colours (`Canvas`, `CanvasText`, `Highlight`, `HighlightText`, `ButtonText`, `ButtonFace`) in forced-colors mode.

### Naming conventions
- CSS: BEM-ish (e.g. `.card`, `.card__header`, `.card__actions`, `.btn`, `.btn--outline`, `.avatar--small`)
- Routes: authenticated actions are namespaced under `our/` (e.g. `Our::ProfilesController`, `Our::GroupsController`)
- Public controllers are at the root namespace (`ProfilesController`, `GroupsController`)
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

### Group nesting & overlapping

The `GroupGroup` join table has a `relationship_type` column with two values:

- **`nested`** (default) — full containment. The child group's entire sub-tree (groups + profiles) appears in the parent. Recursive CTEs follow these links.
- **`overlapping`** — partial overlap (Venn diagram). The child group and its direct profiles appear in the parent, but recursion **stops** — the child's own sub-groups are not pulled into the parent. Visiting the child group directly still shows its full tree.

This is implemented via recursive CTEs in `Group` model methods (`descendant_group_ids`, `descendant_tree`, `descendant_sections`). The CTE tracks a `recurse_further` flag based on relationship type.

Key methods in `Group`:
- `descendant_group_ids` — returns IDs of all descendant groups (respecting overlapping boundaries)
- `all_profiles` — all profiles reachable from this group (direct + descendants)
- `descendant_tree` — nested hash structure for sidebar tree rendering
- `descendant_sections` — flat list of groups with their direct profiles for page sections
- `build_tree` / `walk_descendants` — tree-building helpers that stop at overlapping boundaries

### UUIDs
All profiles and groups use `SecureRandom.uuid` (stored as `uuid` column) for public URLs. Internal IDs are standard Rails auto-increment integers used only in authenticated routes.

## File structure highlights

```
app/controllers/our/   — authenticated (profiles, groups CRUD)
app/controllers/       — public (profiles, groups, group_profiles show)
app/views/our/         — management views (HAML)
app/views/             — public views (HAML)
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

4. **Overlapping vs nested in tests**: When testing overlapping relationships, remember that the overlapping group itself and its direct profiles ARE visible in the parent — only its sub-groups are hidden from the parent's view.

## Deployment

- Hosted on **Scalingo** (Heroku-like PaaS)
- `Procfile` handles web process and post-deploy migration
- `.buildpacks` uses APT + Ruby buildpacks (APT installs libvips for image processing)
- S3-compatible storage for Active Storage in production
- Environment variables: `DATABASE_URL`, `SECRET_KEY_BASE`, `APP_HOST`, `ACTIVE_STORAGE_SERVICE`, `S3_*`
