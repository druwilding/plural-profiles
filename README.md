# Plural Profiles

A web app for pluralfolk to create and share multiple profiles. Each account can have any number of profiles (with a name, pronouns, description, and avatar) and organise them into groups. Profiles and groups get unique shareable URLs, so you can give someone a link to a specific profile or a group of profiles without exposing anything else about your account.

## Features

- **Email & password authentication** — sign up, sign in, sign out, password reset, and email verification (built on Rails 8's built-in authentication generator)
- **Multiple profiles per account** — each with a name, pronouns, description, and avatar image (via Active Storage)
- **Groups** — organise profiles into named groups with a description
- **Group nesting** — groups can contain other groups. Each parent→child link has a configurable inclusion mode; when the child has sub-groups of its own, the mode controls how much of its sub-tree appears in the parent:
  - **All** — all of the child's profiles and sub-groups appear in the parent's tree
  - **Selected** — only specific direct sub-groups of the child are included in the parent; those sub-groups' own children are not automatically pulled in, and sub-groups not in the list are excluded. The `include_direct_profiles` flag on the edge controls whether the child's own direct profiles are pulled in too
  - **None** — only the child's direct profiles appear in the parent; its own sub-groups remain private to it. Visiting the child group directly still shows everything
- **Deep inclusion overrides** — any edge can carry per-target-group overrides (stored in `inclusion_overrides`) that rewrite that target group's inclusion settings *in the context of this edge only*, without affecting the target group's own view or any other parent's view. This enables precise, depth-unlimited control — e.g. excluding a sub-sub-sub-group from one top-level group while leaving it fully visible everywhere else
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
Group   ←→ Group (many-to-many through GroupGroup, with inclusion_mode: all | selected | none)
GroupGroup → has_many InclusionOverrides (context-dependent deep overrides)
InviteCode — belongs to the generating User; records redeemed_by (User) and redeemed_at once used
```

The `GroupGroup` join table connects parent and child groups. Each link has:

- `inclusion_mode` — controls how much of the child group's sub-tree is pulled into the parent:
  - `all` (default) — the child's entire sub-tree (groups and profiles) is included.
  - `selected` — only the direct sub-groups listed in `included_subgroup_ids` are included in the parent. Those sub-groups' own children are not automatically pulled in, and sub-groups not in the list are excluded.
  - `none` — the child group only partially overlaps with the parent. When viewing the parent, the child group appears but recursion stops there. Visiting the child group directly still shows its full tree.
- `include_direct_profiles` (boolean, default `true`) — whether the child group's own direct profiles are pulled into the parent's tree. Setting this to `false` lets you include a group's sub-structure without pulling in its top-level members.
- `has_many :inclusion_overrides` — per-target-group settings that override `inclusion_mode`, `included_subgroup_ids`, and `include_direct_profiles` for a specific descendant group *in the context of this edge only*. This enables deep, context-specific exclusions at any depth without affecting the target group's own view.

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
| `three` | three@example.com | Phase 1 deep-inclusion scenario (see below)                |

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

#### User `three` — deep-inclusion scenario

Nine groups and eight profiles, arranged to demonstrate and test the deep-inclusion override features planned in `docs/plan-deep-inclusion-overrides.md`.

**Alpha Clan tree** (deep-exclusion test):

```
Alpha Clan  ← Grove (direct)
  └── Spectrum (all)
        └── Prism Circle (all)  ← Ember, Stray
              └── Rogue Pack (all)  ← Stray (again — repeated profile test)
```

Stray appears in both Prism Circle and Rogue Pack (repeated profile). The goal of the upcoming override feature is to be able to exclude Rogue Pack from Alpha Clan's view, without removing it from Spectrum's view.

**Delta Clan tree** (selected sub-groups + direct profile exclusion):

```
Delta Clan  ← Shadow (direct)
  ├── Flux [selected: echo_shard only]
  │     ├── Echo Shard (all)  ← Mirage
  │     └── Static Burst (all)  ← Spark  [excluded from Delta Clan — not selected]
  └── Delta Flux (all)
```

Flux has `inclusion_mode: selected` with only Echo Shard in `included_subgroup_ids`. The `include_direct_profiles` flag on the edge controls whether Flux's own direct profiles are pulled in. This means:
- Mirage (in Echo Shard) **should** appear in Delta Clan
- Drift and Ripple (direct Flux members) appear only when `include_direct_profiles: true` on the edge; setting it to `false` excludes them
- Spark (in Static Burst) **should not** appear in Delta Clan (not in selected list)

#### Seeding the development database

To create the Phase 1 scenario in your local development database, pass the email address of the account you want to seed into:

```sh
bin/rails runner script/phase1_seed.rb "you@example.com"
```

If no email is given, it falls back to user id 1:

```sh
bin/rails runner script/phase1_seed.rb
```

The script is safe to re-run — it checks for an existing Alpha Clan group first and exits early if found.

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
