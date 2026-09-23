# Plan: Admin-managed Emotes

## Overview

Today every heart is a hardcoded entry in `HeartEmoji::ALL` with a matching file in `public/images/hearts/`. Adding, reordering, or renaming one needs a code change and a deploy.

This plan moves emotes into the database. Admins can then manage them from the site:

1. **Upload** png, webp, or svg files, one or many at once. Files are added straight away; only files whose name is already in use (or unusable) ask what to do.
2. **Name** each emote. The name comes from the filename at first and can be changed at any time. Names also set the order: `02_spring_heart` sorts before `03_hunter_heart`.
3. **Rename quickly** on one page that shows every emote with a text box for its name.
4. **Group** emotes (e.g. "Hearts", "Other"). Groups are stored in the database and shown as sections in every picker.
5. **Archive** emotes instead of deleting them, so text and profiles that already use them don't break.

Two hard requirements:

- **Nothing that works today may break.** `:cadbury_heart:`, `;cadbury-heart;`, `:48_cadbury_heart:` and every picked profile heart must keep rendering, even after the emote is renamed to `50cadbury_heart` or `chocolate_heart`.
- **Codes that don't follow the heart pattern must work.** A file called `100.png` is typed as `:100:`. The current pattern only matches codes ending in `_heart`, and the current number-stripping rule would turn `100` into an empty string. Both need to change.

v1 has site-wide emotes only. The schema and code are shaped so that **chat-server emotes** and **personal (account) emotes** can be added later without a rewrite (see [Future: scoped emotes](#future-scoped-emotes)).

---

## Decisions so far

| Question               | Decision                                                                                                                                                                                                                 |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Who can manage emotes  | Users with the existing `users.admin` flag, guarded by `ApplicationController#require_admin`                                                                                                                             |
| Typed code             | Both `:spring_heart:` and `:02_spring_heart:` work. The code that gets suggested and inserted drops the number prefix, except for names like `100` or `1st_place`. It's derived automatically and admins can override it |
| Renames                | The old code is kept as an alias automatically and keeps rendering. Stored text (including profiles' emotes) is never rewritten                                                                                          |
| Profile emotes         | A plain **Emotes** text field, like pronouns, so emotes can repeat and go in any order. Replaced the checkbox grid                                                                                                       |
| Deleting               | Archive by default: an archived emote is hidden from pickers but keeps rendering. Permanent delete is a separate action that needs confirming                                                                            |
| Image processing       | The original upload is stored unchanged. A resized, **static** webp is generated for display, so animated uploads show their first frame                                                                                 |
| Bulk upload clashes    | Only clashing files ask for a choice: replace image, skip, or add under a new name                                                                                                                                        |
| Delimiters             | `:x:` and `;x;` (mixed too) for **all** emotes, not only hearts                                                                                                                                                          |
| Profile field label    | "Emotes". New columns `emotes`, `mini_profile_emotes`, `mini_profile_emotes_inherited`                                                                                                                                   |
| Limit on emotes        | None                                                                                                                                                                                                                     |
| Plain-text stand-in    | Every group **must** set a `plain_text` symbol (e.g. ♥ for Hearts)                                                                                                                                                       |
| Activity log           | Not needed                                                                                                                                                                                                               |

---

## Naming model: `name`, `code`, aliases

Each emote has three kinds of identifier. All of them are lowercase `[a-z0-9_]`.

|         | Example           | Purpose                                                                                                                 |
| ------- | ----------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `name`  | `02_spring_heart` | What the admin edits. Sets the sort order within a group. Typing `:02_spring_heart:` works                              |
| `code`  | `spring_heart`    | The canonical code. The picker and autocomplete insert it, and profiles store it. Derived from `name` unless overridden |
| aliases | `cadbury_heart`   | Old codes, recorded automatically whenever `code` changes. They still resolve                                           |

### Deriving a name from a filename

`"02 Spring-Heart.webp"` → `02_spring_heart`:

1. Drop the extension, then downcase.
2. Turn spaces, hyphens and dots into `_`.
3. Remove anything outside `[a-z0-9_]`, collapse repeated `_`, and trim `_` from both ends.
4. If nothing is left, the file waits on the decision page for a name to be typed in.

### Deriving a code from a name

```ruby
def self.default_code(name)
  return name if name.match?(/\A\d+\z/)                    # "100"       → "100"
  return name if name.match?(/\A\d+(st|nd|rd|th)(_|\z)/)   # "1st_place" → "1st_place"
  name.sub(/\A\d+_?/, "").presence || name                  # "02_spring_heart" → "spring_heart"
end                                                         # "50cadbury_heart" → "cadbury_heart"
```

`code_overridden` (boolean) records whether the admin set the code by hand. While it's false, renaming the emote re-derives the code. The admin page always shows the code next to the name. Any case the heuristic gets wrong (e.g. `2024_recap` → `recap`) is visible there and can be fixed with one edit.

### Uniqueness

Within a scope (site-wide for v1), every name, code and alias must be unique across **all** emotes, archived ones included. A code that is only an alias still counts. If `02_heart` and `03_heart` would both derive `heart`, the second one fails validation with a clear message. The admin then renames it or overrides its code. Taking a code that is currently someone's alias requires removing that alias first. That's a deliberate action on the admin page.

---

## Resolving a typed code

`EmoteRegistry#resolve(raw)` returns an emote or nil:

1. Normalise: downcase, and turn `-` into `_`.
2. Exact match on **name**. This handles `:02_spring_heart:`, `:100:` and `:1st_place:`.
3. Exact match on **code**. This handles `:spring_heart:`.
4. Exact match on an **alias**. This handles `:cadbury_heart:` after a rename.
5. **Legacy fallback.** If the value looks like `/\A\d+_?([a-z].*)\z/`, retry steps 2–4 on the part after the number. This handles old Discord-numbered pastes like `:11_aqua_heart:` and `:50cadbury_heart:`. The capture must start with a letter, so `100` never gets reduced to `00`.

Archived emotes still resolve, so they keep rendering. They're just left out of picker and autocomplete lists.

`HeartEmoji.resolve` has the same fallback rule today, so existing behaviour is kept. `StripHeartEmojiNumberPrefixes` has already normalised the stored profile arrays.

---

## Text pattern

The current pattern only matches codes ending in `_heart`:

```ruby
PATTERN = /[:;]([a-z0-9_-]+[_-]heart)[:;]/i
```

The new pattern matches any code:

```ruby
PATTERN = /[:;]([a-z0-9][a-z0-9_-]*)(?=[:;])/i
```

**Subtle point:** with a generic pattern, an unknown `:foo:` would consume the colon that the next real emote needs. For example, in `ratio 3:2:red_heart:` the text `:2:` is consumed, so `red_heart:` no longer has an opening delimiter. The closing delimiter is therefore matched with a **lookahead** and only consumed when the code resolves. `replace_heart_emojis` becomes a small scanner (`StringScanner` or a manual `gsub` loop over match positions) instead of a single `gsub`. Tests must cover these cases:

- `:red_heart::red_heart:` (back to back)
- `12:30:red_heart:`
- `a:b:c`
- a code inside `<code>`, which must be left alone (as today)

HTML entities (`&amp;`, `&#39;`) are skipped, the same way tags and `<code>` blocks already are. Otherwise the `;` that ends an entity could open an emote code: `&amp;red_heart;` would render as a broken `&amp` followed by a heart.

False positives need an exact emote match. `10:100:` would render a 💯 only if `100` exists, and that trade-off is accepted.

### `plain_field`

`plain_field` is used for page titles and confirm dialogs. Today it replaces every pattern match with `♥`. With a generic pattern, that would turn `:foo:` into `♥`. New behaviour:

- **Known emotes** become their group's `plain_text` symbol. The Hearts group has `♥`. Every group has one, because the field is required.
- **Unknown codes** are left as they are.

---

## Data model

```ruby
create_table :emote_groups do |t|
  t.string  :name, null: false                 # "Hearts"
  t.integer :position, null: false, default: 0 # group order in pickers and on the admin page
  t.string  :plain_text, null: false           # "♥": plain-text stand-in for page titles
  t.references :owner, polymorphic: true       # NULL = site-wide. Future: Chat::Server, User
  t.timestamps
end
add_index :emote_groups, [:owner_type, :owner_id, :name], unique: true

create_table :emotes do |t|
  t.references :emote_group, null: false, foreign_key: true
  t.string   :name, null: false                # "02_spring_heart"
  t.string   :code, null: false                # "spring_heart"
  t.boolean  :code_overridden, null: false, default: false
  t.datetime :archived_at
  t.timestamps
end
add_index :emotes, :name, unique: true         # site-wide only in v1; becomes scoped later
add_index :emotes, :code, unique: true

create_table :emote_aliases do |t|
  t.references :emote, null: false, foreign_key: true
  t.string :code, null: false
  t.timestamps
end
add_index :emote_aliases, :code, unique: true
```

- `Emote has_one_attached :image`, with a named variant:
  ```ruby
  has_one_attached :image do |attachable|
    attachable.variant :display, resize_to_limit: [64, 64], format: :webp, preprocessed: true
  end
  ```
  64px covers the largest display size (32px picker) at 2x. vips loads only the first frame by default, so animated webp and png come out static. `preprocessed: true` generates the variant after upload, so the first page view doesn't have to.
- The unique indexes are site-wide in v1. Uniqueness *across* tables (a name clashing with an alias) is checked in the model. Writes are admin-only and rare, so a race here isn't a real concern.
- Moving an emote to another group is allowed. When scopes exist, moves will be limited to groups in the same scope.
- `after_commit` on all three models bumps the registry cache version (below).

### Profiles' emotes are text

Profiles used to store picked hearts as a jsonb array of codes (`heart_emojis`, and `mini_profile_heart_emojis` for chat), picked from a checkbox grid. People wanted to repeat hearts and choose their order, so this became a plain text field, `emotes` (and `mini_profile_emotes` / `mini_profile_emotes_inherited`), that behaves exactly like pronouns: the emote picker button and autocomplete, rendered with `formatted_inline`, no special validation.

`AddEmotesTextToProfiles` copied each profile's picked hearts over in order as codes (`[dewdrop_heart, red_heart]` → `:dewdrop_heart: :red_heart:`). The old columns are ignored by `Profile` and dropped in the cleanup phase.

---

## `EmoteRegistry`: fast lookups

`replace_heart_emojis` runs on every formatted field of every page, including every chat message, so it can't query the database each time. It uses a registry built from the database:

```ruby
EmoteRegistry.current   # site-wide in v1; later EmoteRegistry.for(server:, user:)
  .resolve("cadbury_heart") # => Entry(code:, name:, label:, src:, group:, archived:)
  .pickable                 # non-archived entries, ordered by group position, then name
  .version                  # cache key for fragment caches and the head JSON
```

- The registry is built once, into plain Ruby structs with lookup hashes for names, codes and aliases. Each entry's `src` (the variant's proxy path) is computed at build time, so rendering never touches ActiveStorage.
- The built registry is memoised per process and keyed on a **database version**: counts plus `max(updated_at)` of the three emote tables, read with one cheap query per request (memoised in `Current`). Production's cache store is `:memory_store`, which is per process, so a `Rails.cache` counter wouldn't reach other workers. `after_commit` on the three models clears the `Current` memo, so the rest of the same request sees the change.
- **Order is natural sort on name**, so `2_x` sorts before `10_y` even without zero-padding. The sort happens in Ruby when the registry is built.
- `label` is the code with underscores shown as spaces (`spring heart`), the same as `HeartEmoji.display_name` today.

`HeartEmoji` becomes a thin facade over the registry during the transition. It's removed in the cleanup phase.

### Serving images

- Image URLs use `rails_storage_proxy_path(emote.image.variant(:display))`, which gives:
  - a stable URL, unlike the 24h-expiring redirect URLs set by `service_urls_expire_in`;
  - a long-lived public cache header, so browsers and any CDN cache it for good.

  Rendered chat HTML embeds these URLs, so they must not expire. `theme_helper.rb` already uses the proxy for backgrounds.
- Replacing an emote's image creates a new blob, so the URL changes and nothing serves a stale image from cache.
- **The original SVG is never served to browsers.** Everything shown uses the rasterised webp variant, which avoids SVG script/XSS problems entirely. Originals are kept only in storage, for later reprocessing.
- The `<img>` keeps `class="heart-inline"` (themes may target it) and adds `emote-inline`. Non-square emotes: the variant keeps its aspect ratio (`resize_to_limit`). The inline `<img>` sets `height="24"` and the CSS adds `width: auto; max-width: …`, so a wide emote isn't squashed.

SVG support on the server (librsvg) isn't needed: SVGs are converted in the browser.

---

## Importing the existing 50 hearts

A **data migration** (`ImportHeartsAsEmotes`), so it runs automatically in `postdeploy` and exactly once per environment. A rake task could be forgotten, and one re-run on every deploy would bring back hearts an admin had since deleted. It:

1. Create the group **Hearts** (`position: 0`, `plain_text: "♥"`).
2. For each entry in the current `HeartEmoji::ALL` order, create an emote with:
   - `name`: `"%02d_%s" % [index + 1, heart]`, giving `01_dewdrop_heart`, `02_spring_heart`, `03_hunter_heart`, and so on. That matches the admin's own naming convention.
   - `code`: the current name, e.g. `dewdrop_heart`, so everything already stored keeps resolving without aliases.
   - the image attached from `public/images/hearts/<heart>.webp`.
3. Skip any code that already exists.

`public/images/hearts/` stays in the repo until production has been checked. It's deleted in the cleanup phase.

Tests get a fixture group and all 50 hearts as fixture emotes, so existing tests behave the same as production. Their images live in `test/fixtures/files/emotes/`, named after each emote (`01_dewdrop_heart.webp`), and the emote, blob and attachment fixtures are generated from those filenames (`test/test_helpers/emote_fixture_helper.rb`).

---

## Admin UI

The routes live under a new `admin` namespace. The controllers inherit a `before_action :require_admin`.

```ruby
namespace :admin do
  resources :emotes, only: [:index, :update, :destroy] do
    member     { patch :archive; patch :restore; delete :remove_alias }
    collection { get :upload; post :review; post :import }   # phase 4
  end
  resources :emote_groups, only: [:create, :update, :destroy] do
    member { patch :move }
  end
end
```

Groups are managed inline on the emotes page, so they have no index, new or edit pages of their own.

Add an "Emotes" link in the account/sidebar area, visible only to admins, next to the existing admin-only shared-theme controls.

### Emotes page (`/admin/emotes`)

- One section per group, in `position` order, with its emotes in natural name order.
- Each row shows:
  - a 64px preview;
  - the **name text box**;
  - the derived **code** (`:spring_heart:`), with a small "override" toggle that turns it into an editable box;
  - any **aliases** as chips, each with a remove button;
  - a **group select**;
  - an **Archive** button.
- **Quick rename:** every row is its own small form. A tiny Stimulus `auto-submit` controller submits it on `change` (blur) or Enter. The server replies with a Turbo Stream that:
  - on success, replaces the **whole list** (`#emote-sections`), so the row moves to its new sorted position, even into another group. That's simpler than working out which sections changed, and the list is small. A status line (`role="status"`) says what was saved;
  - on failure, replaces only that row, showing validation errors inline (e.g. "code `heart` is already used by 03_heart").

  A `preserve-focus` controller puts focus back on the element with the same id after the re-render. Enter keeps focus in the renamed field, which has moved with its row. Tab keeps it on whatever field the admin moved to.
- A filter box at the top narrows the rows client-side by name, code or alias.
- An **Archived** section at the bottom, collapsed, has Restore and **Delete permanently** buttons. The delete button uses `turbo_confirm` to spell out the consequence: codes in text will show as plain text again, and the emote is removed from profiles.
- A group management card lets admins add, rename or reorder groups (move up/down) and set `plain_text`. These use ordinary Save buttons and redirects rather than auto-submit, since group edits are rare. The symbol is required and limited to a few characters (validated as 1–4 grapheme clusters, so a single emoji or ♥ fits). A group can only be deleted when it's empty.

### Upload and bulk upload (one flow)

Uploading a single file is just an upload of one. *(Simplified from the original plan: there's no review step for files that can be added as they are.)*

1. **Upload** (`GET /admin/emotes/upload`): a multi-file input with drag and drop, `accept=".png,.webp,.svg"`, and a group select.
2. **Process** (`POST /admin/emotes/upload`, `EmoteUpload.process`): every file is checked; each one that can be added as is, is added straight away, named from its filename. Rejected files (wrong type, too large, unreadable) are listed in a flash message.
3. **Decisions** (only if needed): files whose name or code is already in use, or with no usable name, are stored as **unattached blobs** and shown on a "Choose what to do" page. Each has radio buttons:
   - **Give the existing emote this image** (the default for a clash with an existing emote);
   - **Add it as a new emote**, with a name box (checked automatically when the name is edited, with a live note on the code it will get, or that the name is taken too);
   - **Skip this file** (the default when two files in the same upload share a name: the first is added, the second clashes with it).
4. **Resolve** (`POST /admin/emotes/resolve`) applies the decisions in one transaction. If any fails, nothing is saved and the page comes back with errors, using the same stored files. Skipped files are purged.
5. **Orphan cleanup:** a daily job, `PurgeOrphanEmoteUploadsJob` (4am, in `config/recurring.yml`), purges unattached blobs older than 24 hours that were created by an upload. They're tagged with blob `metadata: { emote_upload: true }`.

### SVGs are converted in the browser

Rails 8.1.3.1 disables libvips' "unfuzzed" loaders, SVG included, because they aren't hardened against malicious files. Rather than re-enable it for the whole app, the upload page draws each SVG on a canvas in the admin's browser (longest side 256px, keeping its shape) and uploads the PNG instead, keeping the file name. The server never reads SVG: one that arrives unconverted (JavaScript off, or a PNG that's really SVG) is rejected with a message. This also keeps the door closed when non-admins can upload emotes later. The original SVG isn't kept.

### Upload validation

- The content type is **sniffed** from the file bytes (Marcel) rather than trusted from the filename or browser. Allowed types are `image/png` and `image/webp`.
- Maximum size is 2 MB per file (originals are kept at full size) and 50 files per upload.
- The display variant must generate. Otherwise the file is rejected as unreadable.

---

## Where users see emotes

### Profile emotes (profile form and chat identity form)

- An **Emotes** text field right after Pronouns, with the emote picker button and autocomplete, like every other emote field. The chat settings page uses the standard "Use main / Set for chat" card for it.
- Shown next to the pronouns in every profile header and the chat mini-profile, as `formatted_inline(profile.emotes)` in `.pronouns__emotes`.
- Archived and deleted emotes behave as in any other text: archived ones still render; a deleted one's code shows as plain text.

### Picker dialog and autocomplete (`heart_input_controller.js`)

- The emote JSON (`heart_emojis_json_tag`) comes from `EmoteRegistry#pickable`. It's rendered at the end of the `<body>`, not in the `<head>`: Turbo replaces the body on every visit but never removes old head scripts, so a head copy went stale after emotes changed. The JS re-parses it whenever the element changes:
  - each entry has `{ code, name, label, src, group }`;
  - the entries are wrapped in a fragment cache keyed on the registry version.
- The **dialog** is titled "Choose an emote", with a "Search emotes…" box. While browsing it shows a heading per group; a search shows one list of matches, best first, without headings. Buttons show the full label ("spring heart"). Up/Down arrows move to the nearest emote in the row above or below by position, since each group's grid has its own rows. *(Done early, alongside phase 3.)*
- **Autocomplete** matches on code *and* name, so typing `:02` finds `02_spring_heart`, and still inserts the canonical `:spring_heart:`. Matches are ranked: exact name or code, then codes starting with the query, then names starting with it, then codes containing it. So `:10` offers `:100:` before `10_aqua_heart`.
- `normaliseQuery` no longer strips leading digits outright. Otherwise `:10` could never find `:100:`. Instead, the query is matched against the name as typed, and against the code with the number prefix stripped.
- The "don't match every `_heart` suffix" rule becomes: match anywhere in the code, but rank prefix matches first, then group order, then name order.

### Rename side effects

When an emote's `code` changes, an `EmoteAlias` is created for the old code, inside the same transaction. Stored text (descriptions, chat messages, profiles' emotes) is **never rewritten**: the alias keeps it rendering.

---

## Future: scoped emotes

Nothing below is built in v1, but the v1 design shouldn't block any of it:

- **Ownership lives on the group.** `emote_groups.owner` is polymorphic: `NULL` means site-wide, `Chat::Server` means server emotes, `User` means personal emotes. An emote's scope is its group's scope.
- **Registry per context.** `EmoteRegistry.for(server: nil, user: nil)` merges site + server + personal registries, each cached separately under its own version. Rendering helpers (`formatted_inline`, `formatted_description`, `replace_heart_emojis`) gain an `emote_scope:` keyword. It defaults to site-wide, so v1 call sites don't change:
  - a chat channel view passes its server;
  - a profile, group, or chat identity passes its owning user.
- **Permissions via a policy object.** `EmotePolicy.new(Current.user).manage?(group)` returns true for:
  - admins, on site groups;
  - the server owner, on that server's groups;
  - the user, on their own groups.

  The admin controllers are written against `@scope` / `@groups`, so the same views can later be mounted at `/chat/servers/:id/emotes` and `/our/emotes`.
- **Uniqueness becomes per scope.** The site-wide unique indexes on `emotes.name`, `emotes.code` and `emote_aliases.code` would move to `(scope_key, code)`, with `scope_key` stored on the emote row, e.g. `"site"`, `"server:12"`, `"user:7"`.
- **Open questions for later** (no need to answer now):
  - **Shadowing.** Can a server emote reuse a site code, and if so, which one wins? Suggestion: site codes are reserved, so scoped emotes can't reuse them.
  - **Portability.** A message using server emote `:ourcat:` is stored as plain text. If it's shown outside that server (quoted, exported), it renders as text. Discord solves this by storing `<:name:id>`. We could do the same at save time if it matters.
  - **Picking scoped emotes on a profile.** Personal emotes on your own profile make sense. Server emotes probably shouldn't be pickable there.
  - **Quotas** per server or account, and whether non-admin uploads need moderation.

---

## Security

- Every emote management endpoint uses `require_admin`. The JSON clash-check endpoint does too.
- SVGs never reach the server: they're converted to PNG in the admin's browser (see [SVGs are converted in the browser](#svgs-are-converted-in-the-browser)).
- Content types are sniffed from the bytes, and there are size and count limits.
- Names and codes are restricted to `[a-z0-9_]`, so they're safe inside the generated `<img>` `title`/`alt` attributes (they're escaped anyway).

---

## Files

**New:**
- `db/migrate/…_create_emote_groups_emotes_and_aliases.rb`
- `app/models/emote_group.rb`, `app/models/emote.rb`, `app/models/emote_alias.rb`
- `app/models/emote_registry.rb`
- `db/migrate/…_import_hearts_as_emotes.rb`
- `app/controllers/admin/base_controller.rb`, `admin/emotes_controller.rb`, `admin/emote_groups_controller.rb`
- `app/views/admin/emotes/{index,upload,decide}.html.haml` plus row/section partials, and `app/views/admin/emote_groups/index.html.haml`
- `app/javascript/controllers/auto_submit_controller.js`, `preserve_focus_controller.js`, `emote_filter_controller.js`, `emote_upload_controller.js`, `emote_upload_decision_controller.js`
- `app/models/emote_upload.rb`, `app/jobs/purge_orphan_emote_uploads_job.rb`
- `db/migrate/…_add_emotes_text_to_profiles.rb`
- Fixtures: `test/fixtures/emote_groups.yml`, `emotes.yml`, `emote_aliases.yml`, plus attachment fixtures

**Changed:**
- `app/models/heart_emoji.rb`: becomes a facade over `EmoteRegistry`, then removed
- `app/helpers/application_helper.rb`: `replace_heart_emojis` (scanner + registry), `plain_field`, `heart_emojis_json_tag`
- `app/models/profile.rb`: the `emotes` text field replaces the heart array, its setters and validations
- `app/views/our/profiles/_form.html.haml`, `app/views/our/chat_identities/edit.html.haml`: Emotes text field instead of the checkbox grid
- Profile headers and the chat mini-profile: `.pronouns__emotes` instead of `shared/_heart_list` (removed, with `heart_picker_controller.js`)
- `app/javascript/controllers/heart_input_controller.js`: grouped dialog, name + code matching
- `config/routes.rb`, account/sidebar nav (admin link)

---

## Tests

- **Name/code derivation:**
  - `02_spring_heart` → `spring_heart`
  - `50cadbury_heart` → `cadbury_heart`
  - `100` → `100`
  - `1st_place` → `1st_place`
  - `"02 Spring-Heart.webp"` → `02_spring_heart`
  - an all-symbol filename → blank name, flagged
- **Resolution:** name, code, alias, legacy number prefix (`11_aqua_heart`), hyphens, case, archived emotes still resolving, unknown → nil. Also `100` must not strip to `00`.
- **Rendering:**
  - `:100:` and `;cadbury-heart;`
  - `:red_heart::red_heart:` and `12:30:red_heart:`
  - `:unknown:` left as it is
  - codes inside `<code>` and attributes untouched
  - `plain_field` with a heart, a non-heart and an unknown code
- **Uniqueness:** a name clashing with another emote's code; a code clashing with an alias; re-deriving on rename; override stops re-deriving.
- **Rename:** alias created, old code still renders in a chat message and in a profile's emotes.
- **Archive/restore/delete:**
  - an archived emote is missing from pickable lists but still renders;
  - after a hard delete, its codes render as plain text.
- **Registry cache:** a change to any model bumps the version, and a fresh registry reflects it.
- **Admin access:** non-admins are redirected from every endpoint.
- **Upload flow (system tests):**
  - bulk upload of png + webp + svg → review → import;
  - clash → replace image;
  - clash → add as new with a new name;
  - invalid type rejected;
  - a validation error on import keeps the uploaded files.
- **Quick rename (system test):** edit a name, blur, and the row moves to its new sorted position with the new code shown.
- **Existing heart tests** (`heart_input_test.rb`, `heart_input_composer_test.rb`, profile tests) pass against fixtures.

---

## Suggested phasing

Each phase is its own PR and leaves the site working.

1. **Database + registry + import.** Migrations (including the heart import), models, `EmoteRegistry`, and `HeartEmoji` as a facade. There's no visible change: hearts now come from the database and are served via ActiveStorage variants.
2. **Generic codes.** The new pattern with the lookahead scanner, name/alias/legacy resolution, `plain_field` changes. `:100:` works from this point on.
3. **Admin emotes page.** Grouped list, quick rename, code override, aliases, archive/restore/delete, group management, and the rename/delete jobs.
4. **Upload + bulk upload**: automatic import, a decision page for clashes, in-browser SVG conversion, and orphan cleanup.
5. **Pickers and profile emotes.** Dialog sections by group *(done)*; profiles' checkbox grid replaced by an Emotes text field, with existing picks migrated *(done)*; autocomplete matching on names as well as codes *(done)*.
6. **Cleanup.** Delete `public/images/hearts/` and `HeartEmoji`. Drop the old `heart_emojis`, `mini_profile_heart_emojis` and `mini_profile_heart_emojis_inherited` columns (and their `ignored_columns` entry). Optionally, do a mechanical rename of `heart_input` / `heart_field` / `heart_emojis_json_tag` to `emote_*`.

