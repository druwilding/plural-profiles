# Plan: Journal, starting as an accessible Dreamwidth client

## Summary

Dreamwidth is moving to a new version of its site that breaks accessibility needs some of our people rely on. The current version works for them; the new one won't. This plan adds a Journal section (`/journal`) to plural-profiles that lets someone list, write and edit their Dreamwidth entries through plain, server-rendered HTML forms, wearing the plural-profiles theme they already use.

It's deliberately the first step towards a native journal in plural-profiles (with importing from Dreamwidth), so the pieces are named and placed with that in mind. But v1 is only a Dreamwidth client: Dreamwidth stays the source of truth, and plural-profiles stores nothing but the connection details.

### Key decisions from discussion

- **Built into plural-profiles, not a standalone site.** A static site on GitHub Pages was considered (a beginner could read and fork it, and changes would deploy in a minute). It was set aside because Dreamwidth's APIs send no CORS headers, so a static site would still need a relay in plural-profiles. Long-term logins would then mean either keeping the API key in the browser or a cross-site login into plural-profiles. Our people already use plural-profiles, already have a long-lived session here, and get their themes for free. The cost we're accepting: changes go through Scalingo deploys, and contributors need to know Rails and HAML rather than plain HTML.
- **Dreamwidth's REST API with an API key, not the old password protocol.** Dreamwidth has a v1 REST API ([spec](https://www.dreamwidth.org/api/v1/spec)) with bearer-token API keys and endpoints to list, read, create and edit entries. The person pastes a key in once, and it keeps working until they revoke it on Dreamwidth. Their Dreamwidth password never touches plural-profiles. The older XML-RPC/flat protocol needs the password on every call (or short-lived session cookies), so it's out.
- **No JavaScript needed.** Every page is a normal HTML form or a list of links. Turbo still runs as it does site-wide, but nothing depends on it.
- **Plain pages under `/journal` on the main domain, not a sub-site (yet).** It's a stop-gap of a few pages, so it doesn't need the work a subdomain brings. It's laid out so it can become a `journal.` sub-site later with mostly a routing change (see "Moving to a sub-site later").
- **Several Dreamwidth accounts per plural-profiles account.** Plural folk often have a Dreamwidth journal each, so one plural-profiles account can connect any number of them, each with its own API key. Which journal you're working in is part of the URL, and every page says so plainly.

---

## Routing

**Plain pages under `/journal` on the main domain, not a sub-site.** For now this is a handful of pages, and the domain dropdown is for real sub-sites. A `journal.` subdomain was in an earlier draft. Leaving it out means no Scalingo custom domain or DNS, no `config.hosts` change, no rewriting header links as full main-site URLs, no cross-origin sign-out workaround, and no `lvh.me` set-up in tests.

- A `scope "journal", module: "journal", as: "journal"` block in `config/routes.rb`, mapping to a `Journal::` controller namespace. (This deliberately isn't under `our/`, even though the pages need a signed-in person; see "Moving to a sub-site later" for why.)
- **Journal pages use the main `application` layout**, with the same header and navigation as the rest of the site, so there's nothing new to style or keep in step.
- **A "Journal" link in the top navigation, next to "Themes"** (`layouts/application.html.haml`), as people have asked, with `aria-current="page"` on journal pages.
- The Profiles/Chat domain switcher is left alone.
- `journal` is already in `User::RESERVED_USERNAMES`, so it can't collide with a future `/:username` route.

### Moving to a sub-site later

If the journal grows into its own sub-site (`journal.`), it should be mostly a routing change, as long as we keep to these:

- **Keep everything in the `Journal::` namespace and under the `/journal` path.** Moving then means wrapping the same routes in `constraints subdomain: "journal"`, as chat does.
- **Add a redirect from the old `/journal/…` addresses** at that point, so bookmarks keep working. Nothing in the database stores journal addresses, so there's nothing to migrate.
- **Use route helpers for every link to journal pages**, never hand-written paths, so the links follow the routes when they move.
- The sub-site work we're skipping now comes back then: the Scalingo domain and DNS record, `config.hosts`, full main-site URLs in the header, and chat's sign-out treatment. Chat has already solved each of these, so it's a known amount of work.

---

## Storing the Dreamwidth connection

### One account, many Dreamwidth connections

The first instinct was to add `dreamwidth_username` and `dreamwidth_api_key` columns to `users`. That can't hold several Dreamwidth accounts, so connections get their own model: **`Journal::DreamwidthConnection`, many per user**, in the `journal_dreamwidth_connections` table.

It's called a *connection*, not an *account*, because the row isn't the Dreamwidth account. It's this person's key to one. The word also matches the pages ("Manage a connection"). Like chat, it sets `self.table_name` explicitly and inherits from an abstract `JournalRecord`.

- **Each connection is separate.** Disconnecting one is just `destroy`; the others and `User` itself are untouched. `has_many … dependent: :destroy` removes them all with the account.
- **It has room to grow** for the import step: `last_imported_at`, import progress, and possibly a community to post to. All of that is per Dreamwidth account.

Shape:

```
Journal::DreamwidthConnection   (table: journal_dreamwidth_connections)
  user_id            (FK)
  username           (string, the Dreamwidth username, normalised: see below)
  api_key            (text, encrypted)
  api_key_digest     (string, HMAC-SHA256 of the key, for spotting duplicates)
  verified_at        (datetime, when Dreamwidth last accepted the key on connect or replace)
  failed_at          (datetime, nullable, when Dreamwidth last rejected the key in use)
  timestamps

  unique index on (user_id, username)
  unique index on (user_id, api_key_digest)
```

**Usernames are normalised before saving and before every lookup:** lowercased, with hyphens turned into underscores. Dreamwidth treats `foo-bar` and `foo_bar` as the same account, and its API only accepts `[0-9A-Za-z_]`. Normalising means the unique index really does stop the same journal being connected twice, and the URL has only one form.

**Why a digest:** encrypted values can't be searched, so on its own `api_key` couldn't tell us "you've already added this key". A digest can. It's an HMAC keyed from `secret_key_base` (via `Rails.application.key_generator`), not a bare SHA-256, so someone holding a copy of the database can't check it against a key they already have.

**When a key stops working.** If someone revokes their key on Dreamwidth, calls start getting 401s. The client reports this as a rejected key, and the controller sets `failed_at`. Every page for that journal then says plainly that Dreamwidth stopped accepting the key, and links to Manage. There they can replace the key (which clears `failed_at` and sets `verified_at`) or disconnect it and add it again. A later successful call also clears `failed_at`.

`User has_many :dreamwidth_connections, class_name: "Journal::DreamwidthConnection", dependent: :destroy`.

- **Unique per plural-profiles account, not site-wide.** Connecting the same Dreamwidth username twice in one account makes no sense. But two plural-profiles accounts both connecting the same journal is legitimate (a shared household journal, say), and refusing it would tell one account that the other exists.
- **No limit on how many** in v1. Each is a single small row.
- **Linking a connection to a profile or group** (so each journal shows that profile's avatar and name) is a natural extension. It also points towards the native journal posting *as* a profile. It isn't needed for v1, and can be added as a nullable `postable` reference later, the same way chat does it.

### Encryption: Active Record encryption, which isn't set up yet

`encrypts :api_key` is a one-liner, but nothing in the app uses Active Record encryption today, so Phase 1 has to set it up:

- Run `bin/rails db:encryption:init` and put the three keys (`primary_key`, `deterministic_key`, `key_derivation_salt`) in `config/credentials.yml.enc`. Production already decrypts credentials via `RAILS_MASTER_KEY` on Scalingo, so there's no new environment variable. Check that the variable is actually set before relying on it.
- Fixed, non-secret keys for the test environment go in `config/environments/test.rb`, so CI doesn't need the master key.
- Non-deterministic encryption. We never look the key up by value.
- **Losing the encryption keys makes every stored API key unreadable.** That's recoverable (people paste their key in again), but it should be written down next to the master key.

### Never shown back, never logged

- After saving, the settings page shows only that a key is connected, its last four characters and when it was last verified, never the key itself. The form's key field is always empty. You replace a key rather than edit it.
- `filter_parameter_logging.rb` already filters anything matching `_key`, so `api_key` is covered. The client sends the key only in the `Authorization` header and never puts it in a URL.

---

## Talking to Dreamwidth: `Dreamwidth::Client`

A plain Ruby class in `app/services/dreamwidth/client.rb`, so it autoloads. It's the first file in `app/services/`. It knows nothing about controllers or plural-profiles models, so the future importer can reuse it as is.

- Built with `Dreamwidth::Client.new(username:, api_key:)`.
- Methods: `entries(count:, offset:, security: nil)`, `entry(id)`, `create_entry(attrs)`, `update_entry(id, attrs)`, `verify!`. Each returns plain Ruby hashes or small value objects, never raw JSON.
- **What the API actually does** (checked in Phase 0; see "Phase 0 findings" below):
  - Entry IDs are Dreamwidth's public `ditemid`, the number in `/29492.html`. One ID works for list, read, edit and the "View on Dreamwidth" link.
  - Editing is `POST /journals/{u}/entries/{id}`, not `PATCH`, and `text` is required every time.
  - Tags go in as a JSON array and come back as one.
  - `datetime` comes back as `"YYYY-MM-DD HH:MM:SS"` in the journal's own time, with no time zone.
  - New entries have no format field, so Dreamwidth uses its default, "casual HTML" (HTML tags allowed, blank lines become paragraphs). That's v1's format. Rich text can come later, perhaps across the whole site.
- **Uses `Net::HTTP` from the standard library, with no new gem.** Nothing in the app makes outbound HTTP calls today, and four endpoints don't justify Faraday.
- **Short timeouts** (around 5 s to open, 15 s to read). A slow Dreamwidth must not hold a Puma thread for long. The app is memory-constrained on Scalingo (see `plan-chat-servers.md`), so we can't spare threads.
- **Errors are mapped to a few kinds the controller can phrase kindly:**
  - rejected key (401/403)
  - not found (404)
  - Dreamwidth unavailable (timeouts, 5xx, 429)
  - validation error (Dreamwidth's message passed through)
- Only ever talks to `https://www.dreamwidth.org/api/v1/`. The host is a constant, never taken from input.

`Journal::ApplicationController` looks up the connection from the URL, always through `Current.user.dreamwidth_connections.find_by!(username: normalised params[:dreamwidth_username])`. Scoping it to the person's own connections means a changed URL can never reach someone else's key: it's a 404. `#dreamwidth_client` then builds the client from that connection. Tests swap that method for a fake (see Testing), so there's no need for WebMock.

### No local copy of entries in v1

Every page fetches what it needs live from Dreamwidth. No caching, no `journal_entries` table. That keeps v1 honest (what you see is what Dreamwidth has) and avoids designing the native journal's schema before we're ready. The import phase is where entries start being stored here.

---

## Pages

All under `/journal`, in the main layout. They're plain forms with the existing pane, form and button classes and theme variables, so everyone's theme applies. Each page has its own `<title>` and a single `h1`.

### Which journal you're in lives in the URL

Every entries page sits under the Dreamwidth username it works on: `/journal/dw/:dreamwidth_username/entries/new`. Switching journals means following a link to another journal's pages. We considered remembering a "current account" in the session or a cookie instead, and decided against it:

- **No hidden state, so no posting to the wrong journal.** With a remembered "current" account, a second tab could switch it, and a form opened before the switch would post somewhere other than the page said. With the username in the URL, the form posts exactly where its page says, always.
- **Bookmarks and the back button just work**, and each journal's pages can be kept open side by side.
- **It costs nothing extra.** It's one route scope and one `find_by!`.

The `dw/` prefix leaves room for native journal pages to sit beside these later, and for other services in theory.

### The pages

| Page                | Route                                                                                                         | What it does                                                                                                                                                                                                                                                                                                                                                                                     |
| ------------------- | ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Journals            | `GET /journal`                                                                                                | The landing page: a list of your connected Dreamwidth accounts, each linking to its Entries page, plus **Connect another Dreamwidth account**. With no connections, it explains what this is and links straight to Connect. With exactly one, it still shows the list rather than redirecting, so the page stays the same whether you have one journal or six.                                   |
| Connect             | `GET /journal/connect`, `POST /journal/connect`                                                               | Dreamwidth username and API key, with a link to get the key (see "Connecting a journal" below). Saving checks the key with Dreamwidth before storing it. It isn't under `dw/`, so a Dreamwidth user called `new` can't clash with it.                                                                                                                                                            |
| Manage a connection | `GET/PATCH /journal/dw/:dreamwidth_username/connection`, `DELETE` the same                                    | Shows that the connection exists (last four characters of the key, when it was last verified, and when Dreamwidth stopped accepting it if `failed_at` is set). It lets you replace the key, or disconnect, with a note that you can also revoke the key on Dreamwidth.                                                                                                                           |
| Entries             | `GET /journal/dw/:dreamwidth_username`                                                                        | That journal's recent entries, newest first. Each shows its subject ("(no subject)" if blank), date, security level, an **Edit** link and a **View on Dreamwidth** link. A **Write a new entry** link sits at the top. Plain "Older entries" / "Newer entries" links page through using `offset`. Until Dreamwidth fixes access-locked entries, see "Fallback while access-locked entries fail". |
| Write               | `GET /journal/dw/:dreamwidth_username/entries/new`, `POST /journal/dw/:dreamwidth_username/entries`           | Subject, entry text (a large `textarea`, sized in `rem`), security (public / access-locked / private) and tags (one comma-separated text field). After posting, it goes back to that journal's Entries with a notice linking to the new entry on Dreamwidth.                                                                                                                                     |
| Edit                | `GET /journal/dw/:dreamwidth_username/entries/:id/edit`, `PATCH /journal/dw/:dreamwidth_username/entries/:id` | The same form, filled with the entry's current values. Our route is `PATCH`; the client sends Dreamwidth a `POST`. Blocked on Dreamwidth fixes; see "Editing mustn't quietly change what isn't shown".                                                                                                                                                                                           |

### Connecting a journal

Dreamwidth has a page, `https://www.dreamwidth.org/api/getkey`, that shows the logged-in account's API key as plain text, and nothing else. If the account has no key yet, it creates one. If nobody is logged in, Dreamwidth asks you to log in and then brings you back to it. (Found in Dreamwidth's source, `DW::Controller::API::REST#key_handler`.) So nobody has to find a key in their settings. The Connect page says:

1. Log in to Dreamwidth as the account you want to connect.
2. **Get your key from Dreamwidth (opens in a new tab).** This link has `target="_blank"` and `rel="noopener"`. The "(opens in a new tab)" is part of the visible link text, so nobody is surprised by it.
3. Copy the key that page shows, then come back to this tab and paste it below.

It also notes, briefly, that the key lets plural-profiles read and post to that journal, and that it can be revoked in Dreamwidth's mobile settings (`/manage/settings/?cat=mobile`).

**Checking what was pasted.** It's easy to be logged in to Dreamwidth as a different account from the one you meant, so saving runs three checks, in this order, each with a plain message that says what to do:

| Check                           | How                                                        | Message                                                                                                                                                                                                                                                                             |
| ------------------------------- | ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Already added this key?         | `api_key_digest` matches another of your connections       | "You've already added this key: it's the one for *otheruser*. Dreamwidth gives each account its own key, so you were probably logged in to Dreamwidth as *otheruser*. Log out of Dreamwidth, log in as *username*, then get the key again."                                         |
| Already connected this journal? | `username` matches another of your connections             | "You've already connected *username*." with a link to its Manage page, to replace the key there.                                                                                                                                                                                    |
| Is it this journal's key?       | `GET /api/v1/journals/{username}/accesslists` with the key | 200 → save. 403 → "That key belongs to a different Dreamwidth account than *username*. Check which account you're logged in to on Dreamwidth." 404 → "Dreamwidth doesn't have an account called *username*." 401 → "Dreamwidth didn't accept that key. Check you copied all of it." |

The `accesslists` call is a reliable ownership check because Dreamwidth answers 403 unless the key's owner *is* `{username}` (`DW::Controller::API::REST::Journals#accesslists_get`). It's also read-only and harmless. The entries endpoints aren't good enough for this: they'd happily list someone else's public entries.

On any failure the form keeps the username, and empties the key field so the next paste doesn't get mixed with the old one.

### Switching journals

- **Every page shows the journal it's for, in the `h1` itself:**
  - Entries: "*username*'s entries"
  - Write: "New entry in *username*"
  - Edit: "Editing an entry in *username*"

  It's the first thing a screen reader announces and the first thing anyone sees, so nobody has to wonder whose journal they're about to post to.
- **The Write form repeats it right beside the submit button** ("Post to *username*"). It's the last thing read before acting.
- **A short "Your journals" `nav` near the top of every journal page** lists each connected account as a link to its Entries page. The current one is marked with `aria-current="page"`, which also has a visible style. It's an ordinary list of links (no dropdown, no JavaScript), so it works the same everywhere. With only one connection it can be left out.
- **The posted notice names the journal too** ("Posted to *username*. View it on Dreamwidth."), as confirmation.

**Not in v1:** deleting entries (the v1 API has no delete endpoint), mood/music/location, icons, comment settings, backdating, posting to communities, and previews. Each can be added later without changing anything above.

### Never lose someone's writing

This is the most important behaviour, and the reason for the rule below.

- **If Dreamwidth rejects or fails a post or edit, re-render the form with everything the person typed still in it.** Don't redirect. Show the error at the top of the form, as text, saying what happened and whether trying again might help.
- After a timeout we can't know whether the entry was actually saved. The message must say that and suggest checking the Entries page before trying again, so nobody ends up with a duplicate post.
- Protect against double-submits with `data-turbo-submits-with` on the submit button. It only works with Turbo, but a double post is annoying rather than harmful.

### Fallback while access-locked entries fail

Until Dreamwidth deploys the access-locked fix (see "Upstream fixes"), reading any access-locked or custom-filtered entry returns a 500. One such entry in a list fails the whole list.

- **The Entries page asks for everything first**, as normal. Once the fix is live, this just works, and we don't need to change or deploy anything.
- **If that returns a 500, it asks for `security=public` and `security=private` separately**, merges them newest first, and shows the first page. Both of those work. A note at the top says: "Access-locked entries can't be shown yet, because of a bug on Dreamwidth's side that has been reported. Your public and private entries are below." "Older entries" is hidden in this mode, since paging two merged lists properly isn't worth building for a temporary problem.
- **The Edit page for an access-locked entry** shows the same explanation and links to editing it on Dreamwidth.
- It's a small amount of code in one place, and it's deleted once the fix is live.

### Editing mustn't quietly change what isn't shown

The form shows only some of an entry's settings. Editing must never reset the rest: custom access filters, mood, icon, comment settings, backdating and so on.

**Phase 0 showed that Dreamwidth's edit endpoint doesn't do a partial update.** The spec marks every field as optional, but an edit that leaves a field out doesn't always keep it:

| Setting                                   | When left out of an edit                    | When sent                              |
| ----------------------------------------- | ------------------------------------------- | -------------------------------------- |
| Subject, security (public/access/private) | kept                                        | changed                                |
| Date, mood, music, location, icon, format | kept                                        | changed (we don't send them)           |
| Tags                                      | **all removed**                             | **mangled** into one tag, `array(0x…)` |
| Comments disabled / no email              | **reset to the journal default**            | changed                                |
| Age restriction and reason                | **reset to the journal default**            | changed                                |
| Backdated ("Don't show on Reading pages") | **unticked**                                | not in the API                         |
| Custom access filter                      | **kept as "custom" with no filters ticked** | not in the API                         |

None of the reset settings come back when reading an entry, so we can't fetch them and send them back either. So:

- **Edit can't ship until Dreamwidth fixes tags on edit.** With the API as it is, every edit either wipes an entry's tags or replaces them with junk. There's no workaround: the API rejects tags sent as a string. It's a small fix that copies what creating an entry already does; see "Upstream fixes".
- **Entries with a custom access filter can't be edited here.** Their Edit page explains why and links to editing the entry on Dreamwidth. We can only tell which entries these are once the access-locked fix is live, since until then reading them fails.
- **Comment settings, age restriction and backdating are reset by any edit**, until Dreamwidth fixes that too. Until then, the Edit form says so plainly, right above the save button: "Saving here resets this entry's comment settings and age restriction to your journal's defaults, and shows it on Reading pages if it was hidden from them. To keep those, edit it on Dreamwidth instead." (See open questions: we may prefer to hold Edit back until this is fixed.)
- Edit loads the entry's **raw source text** (`body_raw` and `subject_raw`, which Dreamwidth includes when the key can edit the entry), not the rendered `body`. Otherwise a single save would convert someone's markup or formatting. (`full=1` is in the spec but does nothing.)
- The client always sends `text`, `subject`, `security` and `tags` on edit, and nothing else.

### Entry text is never rendered as HTML here

Entry bodies only ever go into a `textarea`, which HAML escapes. Subjects are shown as escaped text. We never pass Dreamwidth content through `formatted_description` or `html_safe`. That removes any chance of cross-site scripting through someone's own entries, and means there's nothing to sanitise.

### Accessibility

This is the whole reason the feature exists, so it gets more attention than usual, on top of the existing checklist in `.github/copilot-instructions.md`:

- Every field has a visible `label`. Security uses radio buttons inside a `fieldset` with a `legend` rather than a `select`, so all three options are visible and explained. Hints and errors are tied to their field with `aria-describedby`.
- Errors after a failed submit appear in a summary at the top of the form that lists each problem and links to its field. The summary is the first thing after the `h1`, so it's announced when the page loads.
- Flash notices on journal pages sit directly after the `h1`, rather than above the header, so screen readers reach them in reading order.
- Entries is a real `ol` of links. Each Edit link includes the entry's subject in hidden text ("Edit *Monday thoughts*"), so a list of links read out of context still makes sense.
- Large text, narrow screens and `forced-colors` are checked for every page, as in chat.
- **Before building the pages, ask the people who'll use this what exactly breaks for them in Dreamwidth's new version** (screen reader, keyboard, zoom, motion, cognitive load…). Then put those cases in as browser tests, so we're checking for the same failures in our version.

### Rate limiting

`rate_limit to: 30, within: 1.minute, only: %i[create update]` on the entries controller, plus a lower one on saving the connection (each save calls Dreamwidth to verify the key). As with chat messages, these are set generously and are only there to stop runaway loops, not to limit normal use.

---

## Testing

- **Client:** unit tests for `Dreamwidth::Client` with `Net::HTTP` stubbed through Minitest's `stub`. Cover the response-to-hash mapping, every error kind, the timeouts, and that the key appears only in the `Authorization` header.
- **Controllers and browser tests:** a `FakeDreamwidthClient` in `test/test_helpers/` that keeps entries in memory and can be told to fail in each way. `Journal::ApplicationController#dreamwidth_client` returns it in tests. No outbound HTTP in CI.
- **Browser tests**, ordinary same-domain ones. They cover:
  - connect, then list
  - connect a second account, switch between them using the "Your journals" links, and check each page names the right journal
  - a URL with another account's (or an unconnected) username gets a 404
  - pasting a key already added (it names the other journal), connecting the same journal twice, and a key that belongs to a different account
  - write, then see it listed
  - edit sends exactly `text`, `subject`, `security` and `tags`; a custom-filter entry links to Dreamwidth instead
  - the Entries fallback when the unfiltered list fails, with its note
  - a key that starts being rejected sets `failed_at`, and every page for that journal says so
  - a failed post that keeps the text
  - a timeout message
  - forced colours, using the existing `with_forced_colors`
  - the accessibility cases the people using this give us
- **Fixtures:** a `journal/dreamwidth_connections.yml` fixture with fake keys, including one person with two connections and a second person connected to the same Dreamwidth username. These need the test encryption keys above to load.

---

## Phased build order

**Phase 0: check the API with a real key (no code). Done 2026-10-06.** See "Phase 0 findings" below.

**Phase 1: groundwork and connecting.**
- `/journal` routes and the "Journal" nav link.
- Active Record encryption keys.
- `Journal::DreamwidthConnection`, with as many per account as people like.
- `Dreamwidth::Client` with `verify!` and `entries`.
- The Journals landing page, Connect, Manage a connection (including `failed_at`), the "Your journals" switcher and the Entries list (read-only), with the access-locked fallback.
- Visible to everyone who's signed in, with no admin-only stage.

Ship it. This is already useful for checking things look and read right with real themes and real assistive technology.

**Phase 2: writing.** `create_entry`, the Write page, keeping the text when a post fails, and rate limits. Creating works with the API as it is today.

**Phase 3: editing, once Dreamwidth has fixed tags on edit.** `update_entry` and the Edit page, following "Editing mustn't quietly change what isn't shown". After this, people can stop using Dreamwidth's own pages for everyday posting.

**Later, each with its own planning pass:**
- **Native journal.** Entries stored in plural-profiles, posted *as* a profile or group (the same "postable" idea chat already uses), with their own privacy rules. This is where the journal gets properly plural.
- **Import from Dreamwidth.** Uses `Dreamwidth::Client#entries` to page through everything. Probably a Solid Queue job, since it's long-running.
- **Cross-posting.** Write natively, optionally send to Dreamwidth too.
- **Extra Dreamwidth fields.** Icons (`/users/{u}/icons`), mood/music/location, communities and backdating, added as people ask for them.

---

## Phase 0 findings

Checked on 2026-10-06 with a real key against `druewilding`, using a private test entry for anything that wrote. These match what Dreamwidth's source code predicted.

**Connecting**

- `GET /journals/{u}/accesslists` with the journal's own key returns 200 and its access filters. Another journal returns 403, a made-up username returns 404, and a bad key returns 401. The ownership check works as planned.

**Reading**

- Fields on each entry: `entry_id`, `url`, `subject`, `subject_raw`, `body`, `body_raw`, `datetime`, `security`, `tags`, `icon`, `icon_keyword`, `poster`, and `current_mood`, `current_music` and `current_location` when set.
- `body_raw` is the source as typed (`"<b>bold</b> line one\n\nline two"`). `body` is rendered HTML (`"...line one<br /><br />line two"`). We only ever use the `_raw` fields.
- `datetime` is `"2026-10-06 21:34:00"`, the journal's local time with no time zone.
- `security` is `public`, `private` or (in theory) `access` / `custom`.
- **Reading any access-locked or custom-filtered entry returns a 500**, both alone and in a list. Filtering with `security=public` or `security=private` works. See "Upstream fixes".
- Not yet checked: the largest `count` the list allows (the code defaults to 25).

**Writing**

- Creating returns `{"success": 1, "entry_id": …, "url": …}`. Tags sent as a list are saved correctly.
- Editing returns the same shape. For what an edit keeps and resets, see the table in "Editing mustn't quietly change what isn't shown".
- Tags sent as a string are rejected with a 400, because the request is checked against the spec.

## Upstream fixes

Dreamwidth's code is open source ([dreamwidth/dreamwidth](https://github.com/dreamwidth/dreamwidth)) and actively maintained. Fixing these upstream helps every API user, not just us.

| Problem                                                                                                                                                      | Status                                                                                                                              | What it blocks                                |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| Reading access-locked / custom entries returns 500 (`LJ::Entry::TO_JSON`)                                                                                    | Issue [#3686](https://github.com/dreamwidth/dreamwidth/issues/3686), PR [#3687](https://github.com/dreamwidth/dreamwidth/pull/3687) | The full Entries list; editing locked entries |
| Tags sent as a list are mangled on edit (`LJ::Protocol::editevent` doesn't handle the arrayref that `postevent` does)                                        | To be sent as a PR                                                                                                                  | Edit                                          |
| Edits reset comment settings, age restriction and backdating, and empty custom filters (`DW::Entry::_form_to_backend` rebuilds these from the request alone) | To be reported as an issue. It needs a design decision from Dreamwidth: the API must tell "not sent" apart from "turned off".       | Edit without a warning                        |

---

## Open questions

- **Which accessibility needs, specifically, does Dreamwidth's new version break?** This decides what we test for, and might change the form layout.
- **Ship Edit with a warning, or wait?** Once tags are fixed, should Edit ship with the warning that it resets comment settings, age restriction and backdating? Or should it wait until Dreamwidth fixes those too? A warning is honest, but it's one more thing to read and understand before saving, for exactly the people this is built for.
