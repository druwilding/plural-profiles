# Plural Profiles

A web app for pluralfolk to create and share multiple profiles. Each account can have any number of profiles (with a name, pronouns, description, and avatar) and organise them into groups. Profiles and groups get unique shareable URLs, so you can give someone a link to a specific profile or a group of profiles without exposing anything else about your account.

## Features

- **Email & password authentication** — sign up, sign in, sign out, password reset, and email verification (built on Rails 8's built-in authentication generator)
- **Multiple profiles per account** — each with a name, pronouns, description, and avatar image (via Active Storage)
- **Groups** — organise profiles into named groups with a description
- **Group nesting** — groups can contain other groups, forming trees of arbitrary depth. Each item (group or profile) in the tree can be individually hidden from the parent group's public view using a simple checkbox, with hiding cascading to all descendants
- **Path-scoped visibility** — when the same group appears at multiple points in a tree (diamond pattern), visibility overrides are scoped to the specific traversal path. Hiding a profile via one path doesn't affect its visibility via another path within the same root group
- **Deep inclusion overrides** — per-item hidden state is stored in `inclusion_overrides`, scoped to a root group and a full traversal path (array of group IDs from root to the target's container). This enables precise, context-dependent control without affecting the target's own view or any other parent's view
- **Shareable UUID URLs** — every profile and group gets a unique public URL (e.g. `/profiles/:uuid`, `/groups/:uuid`) that anyone can view without signing in
- **Privacy-conscious sharing** — visitors can only see what you link them to; there's no way to browse from one profile to discover other profiles or groups
- **Invite-only registration** — new accounts require an invite code. Signed-in users can generate up to 10 unused invite codes from their account page to share with people they trust. Each code is single-use and is marked as redeemed when the new account is created

## Tech stack

- **Ruby** 3.3.10
- **Rails** 8.1.2
- **PostgreSQL** 16
- **Puma** web server
- **HAML** templates (via `haml-rails`)
- **Propshaft** asset pipeline
- **Importmap** + **Hotwire** (Turbo & Stimulus)
- **Active Storage** for file uploads
- **BCrypt** for password hashing

## Data model

```
User
 ├── has_many Profiles (name, pronouns, description, avatar, uuid)
 ├── has_many Groups (name, description, avatar, uuid)
 ├── has_many InviteCodes (codes this user generated)
 └── has_many Sessions

Profile ←→ Group (many-to-many through GroupProfile)
Group   ←→ Group (many-to-many through GroupGroup)
Group   → has_many InclusionOverrides (path-scoped per-item hidden state)
InviteCode — belongs to the generating User; records redeemed_by (User) and redeemed_at once used
```

The `GroupGroup` join table connects parent and child groups with no additional columns — it is a simple edge in the group tree.

The `InclusionOverride` table stores per-item hidden state scoped to a root group and traversal path:

- `group_id` — the root group this override applies to
- `path` (jsonb array) — ordered list of group IDs from root (exclusive) to the group containing the target (inclusive). Empty array `[]` means the target is directly on the root group
- `target_type` — `"Group"` or `"Profile"`
- `target_id` — ID of the hidden group or profile

Unique constraint on `(group_id, path, target_type, target_id)` ensures each item can only be hidden once per path per root. Because `path` is an ordered array, the same item can be hidden along one traversal path but visible along another — even when the same `group_group` edge is involved (diamond pattern).

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

| Fixture | Email             | Purpose                                                    |
| ------- | ----------------- | ---------------------------------------------------------- |
| `one`   | one@example.com   | Primary user for most existing tests                       |
| `two`   | two@example.com   | Secondary user (isolation tests, cross-account validation) |
| `three` | three@example.com | Checkbox-model visibility scenario with diamond paths      |

All fixture accounts share the password `Plur4l!Pr0files#2026`.

#### User `one`

Two groups and two profiles:

- **Friends** — contains Alice
- **Everyone** — contains Friends (via a nested group relationship)
- Profile **Alice** (she/her) and **Bob** (he/him)

#### User `two`

One group and one profile:

- **Family** — contains Carol
- Profile **Carol** (they/them)

#### User `three` — checkbox-model visibility scenario

Nine groups and eight profiles, arranged to test path-scoped visibility overrides (the checkbox model). The key feature is a **diamond path**: Prism Circle is reachable via two different routes within Alpha Clan, allowing the same item to be hidden along one path but visible along another.

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

| Path                           | Description                                |
| ------------------------------ | ------------------------------------------ |
| `/`                            | Home page                                  |
| `POST /session`                | Sign in                                    |
| `DELETE /session`              | Sign out                                   |
| `/registration/new`            | Sign up (invite code required)             |
| `/email_verification?token=…`  | Verify email address                       |
| `POST /our/invite-codes`       | Generate a new invite code (auth required) |
| `/passwords/…`                 | Password reset flow                        |
| `/our/profiles`                | Manage your profiles (auth required)       |
| `/our/groups`                  | Manage your groups (auth required)         |
| `/profiles/:uuid`              | Public profile page                        |
| `/groups/:uuid`                | Public group page (lists its profiles)     |
| `/groups/:uuid/profiles/:uuid` | Public profile viewed within a group       |

## Project structure

```
app/
├── controllers/
│   ├── our/
│   │   ├── profiles_controller.rb      # CRUD for the signed-in user's profiles
│   │   ├── groups_controller.rb        # CRUD for the signed-in user's groups
│   │   └── invite_codes_controller.rb  # Invite code generation
│   ├── profiles_controller.rb          # Public profile page
│   ├── groups_controller.rb            # Public group page
│   ├── group_profiles_controller.rb    # Public profile-within-group page
│   ├── registrations_controller.rb     # Sign up (validates invite code)
│   └── email_verifications_controller.rb
├── models/
│   ├── user.rb
│   ├── profile.rb
│   ├── group.rb
│   ├── group_group.rb
│   ├── group_profile.rb
│   ├── inclusion_override.rb
│   └── invite_code.rb
├── views/
│   ├── our/profiles/    # Profile management views
│   ├── our/groups/      # Group management views
│   ├── profiles/        # Public profile view
│   ├── groups/          # Public group view
│   └── group_profiles/  # Public profile-in-group view
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
