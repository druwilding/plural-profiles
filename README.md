# Plural Profiles

A web app for plural people to create and share multiple profiles. Each account can have any number of profiles (with a name, pronouns, description, and avatar) and organise them into groups. Profiles and groups get unique shareable URLs, so you can give someone a link to a specific profile or a group of profiles without exposing anything else about your account.

## Features

- **Email & password authentication** — sign up, sign in, sign out, password reset, and email verification (built on Rails 8's built-in authentication generator)
- **Multiple profiles per account** — each with a name, pronouns, description, and avatar image (via Active Storage)
- **Groups** — organise profiles into named groups with a description
- **Shareable UUID URLs** — every profile and group gets a unique public URL (e.g. `/profiles/:uuid`, `/groups/:uuid`) that anyone can view without signing in
- **Privacy-conscious sharing** — visitors can only see what you link them to; there's no way to browse from one profile to discover other profiles or groups

## Tech stack

- **Ruby** 4.0.1
- **Rails** 8.1.2
- **PostgreSQL** 16
- **Puma** web server
- **Propshaft** asset pipeline
- **Importmap** + **Hotwire** (Turbo & Stimulus)
- **Active Storage** for file uploads
- **BCrypt** for password hashing

## Data model

```
User
 ├── has_many Profiles (name, pronouns, description, avatar, uuid)
 ├── has_many Groups (name, description, uuid)
 └── has_many Sessions

Profile ←→ Group (many-to-many through GroupProfile)
```

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

# Install Ruby 4.0.1 and use the project gemset
# (RVM picks up .ruby-version and .ruby-gemset automatically)
rvm install ruby-4.0.1
rvm use ruby-4.0.1@plural-profiles --create

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

```sh
bin/rails test
```

## Routes overview

| Path                           | Description                            |
| ------------------------------ | -------------------------------------- |
| `/`                            | Home page                              |
| `POST /session`                | Sign in                                |
| `DELETE /session`              | Sign out                               |
| `/registration/new`            | Sign up                                |
| `/email_verification?token=…`  | Verify email address                   |
| `/passwords/…`                 | Password reset flow                    |
| `/our/profiles`                | Manage your profiles (auth required)   |
| `/our/groups`                  | Manage your groups (auth required)     |
| `/profiles/:uuid`              | Public profile page                    |
| `/groups/:uuid`                | Public group page (lists its profiles) |
| `/groups/:uuid/profiles/:uuid` | Public profile viewed within a group   |

## Project structure

```
app/
├── controllers/
│   ├── our/
│   │   ├── profiles_controller.rb   # CRUD for the signed-in user's profiles
│   │   └── groups_controller.rb     # CRUD for the signed-in user's groups
│   ├── profiles_controller.rb       # Public profile page
│   ├── groups_controller.rb         # Public group page
│   ├── group_profiles_controller.rb # Public profile-within-group page
│   ├── registrations_controller.rb  # Sign up
│   └── email_verifications_controller.rb
├── models/
│   ├── user.rb
│   ├── profile.rb
│   ├── group.rb
│   └── group_profile.rb
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

## Deployment

Targeting [Scalingo](https://scalingo.com/) — deployment configuration is not yet set up.

## Licence

All rights reserved.
