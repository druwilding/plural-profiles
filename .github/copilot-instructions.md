# Copilot Instructions — Plural Profiles

These instructions are loaded automatically by GitHub Copilot, both in the editor and for code review. They apply to every conversation in this project. Review-specific guidance is in `.github/skills/code-review/SKILL.md`.

## ⚠️ Language sensitivity — CRITICAL

**Never use the word "system" when referring to plural people.** Not in views, not in code, not in comments, not in variable names, not in test names. It is dehumanising. Use "collective", "group", "household", or simply "account" depending on context.

Plurality is the experience of more than one person sharing a body. This app exists to help plural folk present themselves. Treat this with respect.

The app is written in British English (`lang="en-GB"`): "colour", "organise", and so on, in copy and comments alike.

## Project overview

Two sites in one Rails app:

- **Profiles** (the main domain): plural folk create profiles (name, pronouns, description, avatar) and groups, nest groups inside each other, and share them. Profiles and groups get unique shareable UUID URLs. Visitors can only see what they're linked to — there's no way to browse from one profile to discover others.
- **Chat** (the `chat.` subdomain): Discord-style servers with channels and live messages. People post *as* one of their profiles or groups, chosen per server or per channel, or by typing that profile's proxy brackets (Tupperbox-style).

The two share one database, one account and one session cookie (set for all subdomains).

## Tech stack

| Layer | Technology |
|---|---|
| Language | Ruby 3.3.10 |
| Framework | Rails 8.1.4 |
| Database | PostgreSQL |
| Templates | **HAML** (via `haml-rails`) — not ERB |
| Assets | Propshaft pipeline, hand-written CSS |
| JS | Importmap + Hotwire (Turbo & Stimulus) — no npm, no bundler |
| Live updates | Turbo Streams over Action Cable, with Solid Cable in production |
| Background jobs | Solid Queue (the `worker` process) |
| Uploads | Active Storage (local in development, S3 in production) |
| Auth | Rails 8 built-in authentication generator (`has_secure_password`) |
| Server | Puma |
| Hosting | Scalingo |

## Code conventions

### Views — HAML only
All views use `.html.haml`. Never generate ERB templates. Use HAML syntax for everything, including partials, layouts and Turbo Stream templates.

### CSS — hand-written, no frameworks
The app uses a single `application.css` file with CSS custom properties (see the `:root` block). There is no Tailwind, Bootstrap or any CSS framework.

**All colours must reference the root variables** — never hard-coded hex values, `rgb()` or `rgba()` outside the `:root` block. For tints and transparencies, use `color-mix(in srgb, var(--some-var) X%, transparent)` or `color-mix(in srgb, var(--some-var) X%, var(--other-var))`.

Profile-page variables: `--page-bg`, `--pane-bg`, `--pane-border`, `--pane-text`, `--pane-title-text`, `--pane-link`, `--header-bg`, `--header-text`, `--header-title-text`, `--header-link`, `--primary-button-bg`, `--primary-button-text`, `--primary-button-border`, `--secondary-button-bg`, `--secondary-button-text`, `--secondary-button-border`, `--danger-button-bg`, `--danger-button-text`, `--danger-button-border`, `--input-label`, `--input-bg`, `--input-border`, `--input-text`, `--spoiler`, `--notice-*`, `--alert-*`, `--warning-*`, `--tree-guide`, `--avatar-placeholder-border`.

Chat variables, one set per surface: `--chat-header-*`, `--chat-rail-*` (the server list on the far left, including `--chat-rail-unread-dot`), `--chat-sidebar-*` (the channel list, including `--chat-sidebar-unread-dot`), `--chat-topbar-*` (the channel header), `--chat-pane-*` (the message history), `--chat-composer-*`, `--chat-input-*`, `--chat-divider`, `--chat-spoiler`, `--chat-tree-guide`, `--chat-avatar-placeholder-border`. Use these in chat, not the profile-page ones.

Every themeable colour is a key in `Theme::THEMEABLE_PROPERTIES`, which a person's theme sets as an inline custom property. Each chat key falls back to its profile-page equivalent until a theme sets it. A new colour means a new key there, a `:root` default, and a place in the theme designer.

The one deliberate exception: colours drawn outside the page's CSS, such as the unread badge `chat_unread_controller.js` draws onto the favicon with a canvas. The browser's tab bar isn't themed, so that badge is fixed to read on light and dark tab bars alike.

### Accessibility
This is a core value of the app, not a nice-to-have.

- Consider `@media (forced-colors: active)` for every interactive or visual component. Use system colours (`Canvas`, `CanvasText`, `Highlight`, `HighlightText`, `ButtonText`, `ButtonFace`, `GrayText`) there.
- Size in `rem` so layouts follow the person's text size. The chat in particular has to work at large text sizes on small screens.
- Information shown only visually needs a text equivalent: `.visually-hidden` text (unread dots carry "(unread)"), `aria-*` state, or a `title` plus a keyboard and touch route. A `title` tooltip alone only helps mouse users.
- Hover-only behaviour needs a keyboard (`:focus-visible`) and touch equivalent.
- Decorative glyphs added in CSS use alternative text to stay silent: `content: "– " / "";`.

### Naming conventions
- CSS: BEM-ish (e.g. `.card`, `.card__header`, `.btn`, `.btn--secondary`, `.avatar--small`, `.chat-message__time`)
- Routes: authenticated profile-site actions are namespaced under `our/` (e.g. `Our::ProfilesController`); chat controllers are under `Chat::` and only routed on the `chat` subdomain
- Shared-link controllers are at the root namespace (`ProfilesController`, `GroupsController`)
- Models use singular names; join tables use both model names (`GroupGroup`, `GroupProfile`); chat models live in `Chat::`, and the database-backed ones inherit from `ChatRecord`; journal models live in `Journal::` and inherit from `JournalRecord`

### Comments
Comments explain *why*: the constraint, the browser quirk, the bug a line prevents. Keep them in step with the code; a comment that describes old behaviour is a bug.

### Testing
- **Unit and controller tests:** `bin/rails test` — standard Minitest with fixtures
- **System tests:** `bin/rails test:system` — Capybara + Selenium + headless Chrome
- System test base class is in `test/application_system_test_case.rb`
- Chat system tests visit `http://chat.lvh.me:<port>` (Chrome maps `lvh.me` to localhost) and sign in on the main domain first
- The browser is shared between tests, so a test that resizes the window or emulates media must put it back (see `with_forced_colors`)
- Debug helpers:
  - `HEADLESS=false bin/rails test:system` — run with visible Chrome browser
  - `SLOWMO=true bin/rails test:system` — add 0.5s delays between actions
  - `SLOWMO=2 bin/rails test:system` — custom delay in seconds
- Fixtures are in `test/fixtures/` — prefer fixtures over factory-based approaches
- A regression test should fail without the fix it covers. Check that before relying on it.
- CI runs: `scan_ruby` (brakeman + bundler-audit), `scan_js` (importmap audit), `lint` (rubocop), `test` and `system-test`

### Linting
- RuboCop with Rails Omakase style guide (`rubocop-rails-omakase`)
- Run with `bin/rubocop`, auto-fix with `bin/rubocop -a`

### JavaScript
- Use Importmap for JS dependencies (no npm/yarn/node for the Rails app); vendored packages are pinned with an exact version
- Stimulus controllers go in `app/javascript/controllers/`; a plain module shared between controllers (like `chat_drafts.js`) goes in `app/javascript/` with its own `pin`
- Turbo Drive handles navigation and form submissions; a form that redirects to another origin (between the main domain and `chat.`) must opt out with `data: { turbo: false }`, because Turbo's fetch can't follow a cross-origin redirect

## Data model

```
User
 ├── has_many Profiles  (name, pronouns, description, avatar, uuid, labels, position)
 ├── has_many Groups    (name, description, avatar, uuid, labels, position)
 ├── has_many Themes    (colours and background image; active_theme is the one they see)
 ├── has_many InviteCodes
 └── has_many Sessions

Profile ←→ Group  (many-to-many via GroupProfile, with a position)
Group   ←→ Group  (many-to-many via GroupGroup, with a position)

Chat::Server   (owner, theme, uuid)
 ├── has_many Chat::Memberships  (user, role, default_postable: a Profile or Group)
 ├── has_many Chat::Channels     (name, subtitle, description, theme, uuid)
 │    ├── has_many Chat::Messages  (user, postable, postable_name, body)
 │    ├── has_many Chat::ChannelReads  (user, last_read_at)
 │    └── has_many Chat::ChannelDefaultPostables  (who someone posts as in that channel)
 └── has_many Chat::ServerInvites

EmoteSet → Emotes (with aliases), used in chat messages and in profile and group fields
```

### Group nesting & visibility

`GroupGroup` links parent and child groups. All edges are fully recursive — the CTE follows every link.

Visibility is controlled by `InclusionOverride` records. Each override hides a specific group or profile within a particular root group's tree, scoped by the **traversal path** (an array of group IDs from root to the item's container). This allows the same item to be hidden along one path but visible along another when a group appears at multiple points in a diamond-shaped tree.

Key methods in `Group`:
- `reachable_group_ids` / `descendant_group_ids` — recursive CTE returning all group IDs in the tree
- `all_profiles` — all profiles reachable from this group, respecting path-scoped overrides
- `descendant_tree` — nested hash structure for sidebar tree rendering, applying overrides
- `descendant_sections` — depth-first flat list of groups with their direct profiles for page sections
- `management_tree` — full unfiltered tree with `hidden` / `cascade_hidden` flags for the manage-groups UI
- `overrides_index` — loads all `InclusionOverride` records for a root group into a Set for O(1) lookups during traversal

### Custom ordering

People can drag their groups and profiles into their own order. `position` is nullable: `NULL` sorts after positioned items, then alphabetically (`Positioned#order_by_position_then_name`). Each list's order lives where that list does — top-level groups and the flat profile list on `groups.position` / `profiles.position`, a group's contents on `group_groups.position` / `group_profiles.position` — so the same profile can sit in a different place in each group. `ListOrder` saves a list, and refuses a save from a stale page. Chat pickers stay alphabetical.

### UUIDs
Profiles, groups, servers and channels use a `uuid` column for URLs. Internal IDs are standard Rails integers, never shown in shareable URLs.

## Chat architecture

- **Live updates are pushed, not polled.** `turbo_stream_from` in the chat layout subscribes each page to its channel and the person's own streams. `Chat::Message` broadcasts each new message, and the unread dots, after commit.
- **A broadcast is drawn once, for everyone, in the sender's request** — so in the sender's time zone, and with no idea who's watching. Anything that depends on the viewer is fixed up in their browser: `chat_dates_controller.js` rewrites live message times in the viewer's time zone and adds date dividers.
- **Action Cable has no replay.** Anything broadcast while a page's connection is down is lost, so `chat_reconnect_controller.js` reloads the page to catch up when the connection returns.
- **Unread state** is `Chat::ChannelRead.last_read_at` against the latest message. When someone posts, everyone else in the server is optimistically marked unread, including anyone already reading that channel; their page then marks it read again (`channel_read_controller.js`), but only while the tab is visible and focused. `chat_unread_controller.js` holds newly arrived dots back for a moment so that round trip doesn't flicker, and puts a dot in the tab's favicon and title while anything is unread.
- **Sending a message** answers with an empty Turbo Stream, not a redirect, so the message box is never replaced and a phone's keyboard stays open. The message itself arrives only in the broadcast (sending it in both would let Turbo reorder it). The composer keeps the box read-only until the message appears, and guards against sending twice.
- **Drafts** are kept per account and channel in `localStorage` (`chat_drafts.js`), and cleared on sending or signing out of the chat.
- The chat page is exactly the visible screen (`100dvh`); only the panes inside it scroll.

## File structure highlights

```
app/controllers/our/    — authenticated profile-site management
app/controllers/chat/   — chat (chat. subdomain only)
app/controllers/        — shareable links, sessions, registrations
app/views/our/          — management views (HAML)
app/views/chat/         — chat views (HAML); chat/shared holds the rail, channel list and dots
app/views/layouts/      — application (profiles) and chat layouts
app/models/             — User, Profile, Group, Theme, Emote…; concerns for shared behaviour
app/models/chat/        — chat models
app/javascript/controllers/ — Stimulus controllers
app/assets/stylesheets/application.css — single CSS file, hand-written
test/system/            — Capybara system tests (chat ones are chat_*_test.rb)
docs/                   — plans written before larger features
```

## Common pitfalls

1. **Turbo's page cache**: Turbo keeps a copy of each page to show on going back, and briefly as a preview before a fresh visit. That copy holds whatever the page looked like when it was left: typed text, JS-added classes, a changed `document.title`. Code that changes the page should tidy up on `turbo:before-cache`, or cope with being restored. In system tests, wait for specific content (or for `html[data-turbo-preview]` to go) rather than checking state straight after navigating.

2. **Turbo prefetches links on hover**, so a GET must never change anything. That's why reading a channel is marked by `channel_read_controller.js` after the page appears, not by the channel's GET.

3. **Avatar placeholder sizing**: `.avatar--placeholder` has `min-width: 64px` / `min-height: 64px`. When using a smaller size, set `min-width` / `min-height` on the compound selector too.

4. **Circular group references**: `GroupGroup` validates against circular references (a group can't be its own ancestor). Keep this in mind when creating test fixtures.

5. **Path-scoped overrides**: inclusion overrides use a `path` (jsonb array of group IDs) to scope visibility to one route through the tree. An empty path `[]` means the target is directly on the root group.

6. **Time zones**: pages are drawn in the viewer's zone (their account setting, else their browser's, else UTC; see `ApplicationController#set_time_zone`). Broadcasts aren't — see Chat architecture.

## Deployment

- Hosted on **Scalingo** (Heroku-like PaaS)
- `Procfile` runs `web` (Puma), `worker` (Solid Queue) and migrates on `postdeploy`
- `.buildpacks` uses APT + Ruby buildpacks (APT installs libvips for image processing)
- S3-compatible storage for Active Storage in production
- Environment variables: `DATABASE_URL`, `SECRET_KEY_BASE`, `APP_HOST`, `ACTIVE_STORAGE_SERVICE`, `S3_*`, `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` and `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` (encrypt the journal's Dreamwidth API keys)
