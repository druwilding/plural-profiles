# Plural Profiles

A web app for pluralfolk to create and share multiple profiles. Each account can have any number of profiles (with a name, pronouns, description, and avatar) and organise them into groups. Profiles and groups get unique shareable URLs, so you can give someone a link to a specific profile or a group of profiles without exposing anything else about your account.

## Features

### Profiles & groups

- **Multiple profiles per account** — each with a name, pronouns, description, avatar image (with alt text), and optional heart emojis
- **Groups** — organise profiles into named groups with a description and avatar
- **Group nesting** — groups can contain other groups, forming trees of arbitrary depth. Each item (group or profile) in the tree can be individually hidden from the parent group's shared view using a simple checkbox, with hiding cascading to all descendants
- **Path-scoped visibility** — when the same group appears at multiple points in a tree (diamond pattern), visibility overrides are scoped to the specific traversal path. Hiding a profile via one path doesn't affect its visibility via another path within the same root group
- **Deep inclusion overrides** — per-item hidden state is stored in `inclusion_overrides`, scoped to a root group and a full traversal path (array of group IDs from root to the target's container). This enables precise, context-dependent control without affecting the target's own view or any other parent's view
- **Labels** — profiles and groups can be tagged with labels (stored as a jsonb array). Labels appear in the management UI and can be used to filter listings. They're also central to the duplication feature
- **Group duplication** — a multi-step wizard that deep-copies an entire group tree. The wizard scans for conflicts (existing copies with the same labels), lets you choose to reuse or re-copy each item, previews the result, then executes — copying avatars, edges, and inclusion overrides with remapped paths
- **Heart emojis** — profiles can display custom heart emojis (≈45 hearts like `aqua_heart`, `void_heart`, `dewdrop_heart`), and `:heart_name:` shortcodes in descriptions are rendered as inline images
- **Description formatting** — descriptions support basic HTML (`<b>`, `<i>`, `<u>`, `<s>`, `<details>`, `<summary>`) and `||spoiler||` syntax for togglable hidden text
- **Created-at backdating** — profiles and groups can have their creation date set to a past date

### Sharing & privacy

- **Shareable UUID URLs** — every profile and group gets a unique URL (e.g. `/profiles/:uuid`, `/groups/:uuid`). Currently these require sign-in to view
- **UUID regeneration** — profiles and groups can regenerate their share URL at any time
- **Privacy-conscious sharing** — visitors can only see what they're linked to; there's no way to browse from one profile to discover other profiles or groups
- **Interactive group explorer** — shared group pages feature a tree sidebar that lazy-loads content panels via AJAX, with a flat no-JS fallback for progressive enhancement

### Themes

- **Custom themes** — each account can create themes with a full set of colour overrides (page, pane, buttons, inputs, flash messages) plus an optional background image
- **Theme application** — individual profiles and groups can each have their own theme, or the account's active theme applies site-wide
- **Shared themes** — admins can share themes so all users can browse and duplicate them
- **Site default theme** — one shared theme can be designated as the site default (applied when no other theme is active)
- **Theme import/export** — themes can be exported as JSON and imported by pasting JSON or legacy CSS `:root {}` blocks
- **Override preference** — accounts can choose to always use their own theme on shared pages instead of the page's assigned theme
- **Tag filtering** — themes can be tagged (e.g. `dark`, `light`, `warm-colours`, `high-contrast`) and filtered by tag in the theme browser
- **Background images** — themes support a background image with configurable repeat, size, position, and attachment

### Account & auth

- **Email & password authentication** — sign up, sign in, sign out, password reset, and email verification (built on Rails 8's built-in authentication generator)
- **Account name** — optional username (2–30 chars, lowercase letters/numbers/underscores/hyphens) displayed on the account page
- **Account deactivation** — admin-only action that deactivates an account and terminates all its sessions
- **Email change** — change email with verification sent to the new address plus notification to the old one; pending changes can be cancelled
- **Invite-only registration** — new accounts require an invite code. Signed-in users can generate up to 10 unused invite codes by default (configurable via the `MAX_INVITE_CODES_PER_USER` environment variable) from their account page to share with people they trust. Each code is single-use and is marked as redeemed when the new account is created

## Tech stack

- **Ruby** 3.3.10
- **Rails** 8.1.3
- **PostgreSQL** 16
- **Puma** web server
- **HAML** templates (via `haml-rails`)
- **Propshaft** asset pipeline
- **Importmap** + **Hotwire** (Turbo & Stimulus)
- **Active Storage** for file uploads (local dev, S3 in production)
- **BCrypt** for password hashing

## Data model

```
User
 ├── has_many Profiles (name, pronouns, description, avatar, labels, heart_emojis, uuid, theme)
 ├── has_many Groups (name, description, avatar, labels, uuid, theme)
 ├── has_many Themes (name, colors, background_image, tags, shared, site_default)
 ├── has_many InviteCodes (codes this user generated)
 ├── has_many Sessions
 ├── belongs_to active_theme (Theme, optional)
 ├── username (optional account name)
 └── deactivated_at (admin-set deactivation timestamp)

Profile ←→ Group (many-to-many through GroupProfile)
Group   ←→ Group (many-to-many through GroupGroup)
Group   → has_many InclusionOverrides (path-scoped per-item hidden state)

Profile → copied_from (Profile, optional — tracks duplication lineage)
Group   → copied_from (Group, optional — tracks duplication lineage)

InviteCode — belongs to the generating User; records redeemed_by (User) and redeemed_at once used
```

The `GroupGroup` join table connects parent and child groups with no additional columns — it is a simple edge in the group tree.

The `InclusionOverride` table stores per-item hidden state scoped to a root group and traversal path:

- `group_id` — the root group this override applies to
- `path` (jsonb array) — ordered list of group IDs from root (exclusive) to the group containing the target (inclusive). Empty array `[]` means the target is directly on the root group
- `target_type` — `"Group"` or `"Profile"`
- `target_id` — ID of the hidden group or profile

Unique constraint on `(group_id, path, target_type, target_id)` ensures each item can only be hidden once per path per root. Because `path` is an ordered array, the same item can be hidden along one traversal path but visible along another — even when the same `group_group` edge is involved (diamond pattern).

The `Theme` table stores per-user colour schemes with ≈30 CSS custom property overrides (grouped into base, buttons, forms, flash), optional background image (Active Storage), layout properties (`background_repeat`, `background_size`, `background_position`, `background_attachment`), tags, credit/attribution, and sharing flags.

This allows plural folk to model complex, Venn-diagram-style group arrangements where not every part of one group belongs inside another.

## Getting started

### Prerequisites

- [RVM](https://rvm.io/) (or another Ruby version manager)
- [PostgreSQL 16](https://www.postgresql.org/) — on macOS: `brew install postgresql@16`
- Make sure the PostgreSQL binaries are on your PATH:
  ```sh
  export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"
  ```

### Setup

```sh
# Clone the repo
git clone git@github.com:druewilding/plural-profiles.git
cd plural-profiles

# Install Ruby 3.3.10 and use the project gemset
# (RVM picks up .ruby-version and .ruby-gemset automatically)
rvm install ruby-3.3.10
rvm use ruby-3.3.10@plural-profiles --create

# Install dependencies
bundle install

# Create and migrate the databases
bin/rails db:create
bin/rails db:migrate

# Start the server
bin/rails server
```

The app will be available at [http://localhost:3000](http://localhost:3000).

### Running tests

Unit and integration tests:

```sh
bin/rails test
```

System tests (requires Chrome):

```sh
bin/rails test:system
```

Both suites together:

```sh
bin/rails test && bin/rails test:system
```

Both are run automatically on pull requests via GitHub Actions CI (the `test` and `system-test` jobs).

### Test data

Fixtures live in `test/fixtures/`. Three users are defined:

| Fixture | Email             | Admin | Purpose                                                    |
| ------- | ----------------- | ----- | ---------------------------------------------------------- |
| `one`   | one@example.com   | Yes   | Primary user for most existing tests                       |
| `two`   | two@example.com   | No    | Secondary user (isolation tests, cross-account validation) |
| `three` | three@example.com | Yes   | Checkbox-model visibility scenario with diamond paths      |

All fixture accounts share the password `Plur4l!Pr0files#2026`.

#### User `one`

Two groups and three profiles:

- **Friends** — contains Alice (themed with Dark Forest)
- **Everyone** — contains Friends (via a nested group relationship)
- Profile **Alice** (she/her), **Bob** (he/him), **Everyone Profile** (they/them)

Owns themes: **Dark Forest** (dark, cool-colours), **Sunset** (light, warm-colours), **Ocean Shared** (shared), **Default Shared** (shared, site default)

#### User `two`

One group, one profile, and one theme:

- **Family** — contains Carol
- Profile **Carol** (they/them)
- Theme **Cerulean**

#### User `three` — checkbox-model visibility scenario

Nine groups, eight profiles, and one shared theme (**Another Admin Shared**). The groups are arranged to test path-scoped visibility overrides (the checkbox model). The key feature is a **diamond path**: Prism Circle is reachable via two different routes within Alpha Clan, allowing the same item to be hidden along one path but visible along another.

**Alpha Clan tree** (diamond-path test):

```
Alpha Clan  ← Grove (direct)
  ├── Spectrum
  │     └── Prism Circle  ← Ember, Stray
  │           └── Rogue Pack  [HIDDEN at path spectrum→prism_circle]  ← Stray [HIDDEN at this path]
  └── Echo Shard
        └── Prism Circle  (same group, different path)
              └── Rogue Pack  (visible here — no override for echo_shard path)  ← Stray (visible here)
```

`InclusionOverride` records:
- Hide Rogue Pack at path `[spectrum, prism_circle]` → excluded from Alpha Clan via the Spectrum branch
- Hide Stray at path `[spectrum, prism_circle, rogue_pack]` → excluded via Spectrum branch

Via the Echo Shard branch, no overrides exist — Rogue Pack and Stray are both visible. Viewing Spectrum directly (as its own root) also shows everything, since overrides are scoped to Alpha Clan.

**Castle Clan tree** (selective hiding via overrides):

```
Castle Clan  ← Shadow (direct)
  ├── Flux
  │     ├── Echo Shard  ← Mirage (visible)
  │     └── Static Burst  [HIDDEN at path flux]  ← Spark (cascade-hidden)
  │     ← Drift [HIDDEN at path flux], Ripple [HIDDEN at path flux]
  └── Castle Flux
```

`InclusionOverride` records hide Static Burst, Drift, and Ripple at path `[flux]` within Castle Clan. This means:
- Mirage (in Echo Shard) **appears** in Castle Clan
- Drift and Ripple (direct Flux profiles) are **hidden** from Castle Clan
- Spark (in Static Burst) is **cascade-hidden** from Castle Clan (parent group hidden)
- Viewing Flux directly still shows everything

#### Seeding the development database

To create the test scenario in your local development database:

```sh
bin/rails runner script/phase1_seed.rb
```

The script is safe to re-run — it creates a new user every time with unique groups, profiles and relationships.

### Linting

This project uses [RuboCop](https://rubocop.org/) with the [Rails Omakase](https://github.com/rails/rubocop-rails-omakase/) style guide:

```sh
bin/rubocop
```

Auto-fix issues:

```sh
bin/rubocop -a
```

## Routes overview

| Path                           | Description                                      |
| ------------------------------ | ------------------------------------------------ |
| `/`                            | Home page (at-a-glance dashboard when signed in) |
| `POST /session`                | Sign in                                          |
| `DELETE /session`              | Sign out                                         |
| `/registration/new`            | Sign up (invite code required)                   |
| `/email_verification?token=…`  | Verify email address                             |
| `/passwords/…`                 | Password reset flow                              |
| `/our/account`                 | Account settings (name, email, password, prefs)  |
| `POST /our/invite-codes`       | Generate a new invite code (auth required)       |
| `/our/profiles`                | Manage your profiles (auth required)             |
| `/our/groups`                  | Manage your groups (auth required)               |
| `/our/groups/:id/duplicate`    | Duplicate a group tree (multi-step wizard)       |
| `/our/themes`                  | Manage and browse themes (auth required)         |
| `/profiles/:uuid`              | Shared profile page                              |
| `/groups/:uuid`                | Shared group page (interactive tree explorer)    |
| `/groups/:uuid/profiles/:uuid` | Shared profile viewed within a group             |
| `/stats`                       | Shared aggregate stats page                      |

## Project structure

```
app/
├── controllers/
│   ├── our/
│   │   ├── account_controller.rb       # Account settings (name, email, password, prefs)
│   │   ├── profiles_controller.rb      # CRUD for the signed-in user's profiles
│   │   ├── groups_controller.rb        # CRUD + manage members + duplication wizard
│   │   ├── invite_codes_controller.rb  # Invite code generation and deletion
│   │   └── themes_controller.rb        # Theme CRUD, activate, share, import/export
│   ├── profiles_controller.rb          # Shared profile page
│   ├── groups_controller.rb            # Shared group page + panel (AJAX tree content)
│   ├── group_profiles_controller.rb    # Shared profile-within-group page + panel
│   ├── stats_controller.rb            # Shared stats page
│   ├── registrations_controller.rb     # Sign up (validates invite code)
│   └── email_verifications_controller.rb
├── models/
│   ├── user.rb
│   ├── profile.rb           # includes HasAvatar, HasLabels
│   ├── group.rb             # includes HasAvatar, HasLabels; recursive CTE methods
│   ├── group_group.rb
│   ├── group_profile.rb
│   ├── inclusion_override.rb
│   ├── invite_code.rb
│   └── theme.rb             # colour properties, background image, sharing, tags
├── javascript/controllers/
│   ├── clipboard_controller.js          # Copy-to-clipboard with feedback
│   ├── details_persist_controller.js    # Persist <details> open/closed in localStorage
│   ├── duplicate_resolution_controller.js  # Duplication conflict form validation
│   ├── heart_picker_controller.js       # Progressive enhancement for heart emoji picker
│   ├── spoiler_controller.js            # Toggle ||spoiler|| text visibility
│   ├── theme_designer_controller.js     # Live theme preview, colour sync, JSON export
│   ├── theme_import_controller.js       # Import JSON or CSS :root {} blocks
│   ├── tree_controller.js              # Shared group tree explorer with lazy-loaded panels
│   └── visibility_toggle_controller.js  # Async toggle for inclusion overrides
├── views/
│   ├── our/profiles/    # Profile management views (HAML)
│   ├── our/groups/      # Group management + duplication wizard views (HAML)
│   ├── our/themes/      # Theme management + designer views (HAML)
│   ├── our/account/     # Account settings views (HAML)
│   ├── profiles/        # Shared profile view
│   ├── groups/          # Shared group view + tree explorer
│   └── group_profiles/  # Shared profile-in-group view
└── assets/
    └── stylesheets/
        └── application.css   # Hand-written CSS with custom colour palette
```

## Deployment (Scalingo)

### Prerequisites

- [Scalingo CLI](https://doc.scalingo.com/cli) installed
- A Scalingo account

### Create the app

```sh
scalingo create plural-profiles
```

### Add PostgreSQL

```sh
scalingo --app plural-profiles addons-add postgresql postgresql-starter-512
```

This automatically sets the `DATABASE_URL` environment variable.

### Set environment variables

```sh
scalingo --app plural-profiles env-set \
  SECRET_KEY_BASE="$(bin/rails secret)" \
  APP_HOST="plural-profiles.osc-fr1.scalingo.io" \
  ACTIVE_STORAGE_SERVICE="scalingo"
```

For avatar uploads, you'll need S3-compatible storage (AWS S3, Scalingo Object Storage, etc.):

```sh
scalingo --app plural-profiles env-set \
  S3_ACCESS_KEY_ID="your-key" \
  S3_SECRET_ACCESS_KEY="your-secret" \
  S3_BUCKET="your-bucket" \
  S3_REGION="eu-west-1" \
  S3_ENDPOINT="https://s3.eu-west-1.amazonaws.com"
```

If you don't set up S3 yet, avatars will use local disk storage (which is **ephemeral** on Scalingo — files are lost on redeploy).

### Deploy

```sh
git push scalingo main
```

The `Procfile` runs `db:migrate` automatically after each deploy via the post-deployment hook.

### Configuration files

| File          | Purpose                                                |
| ------------- | ------------------------------------------------------ |
| `Procfile`    | Defines the web process and post-deploy migration hook |
| `.buildpacks` | Uses APT + Ruby buildpacks (APT installs libvips)      |
| `Aptfile`     | Lists APT packages to install (`libvips-dev`)          |

## Licence

All rights reserved.
