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

The first instinct was to add `dreamwidth_username` and `dreamwidth_api_key` columns to `users`. That can't hold several Dreamwidth accounts, so connections get their own model: **`Journal::DreamwidthAccount`, many per user.**

- **Each connection is separate.** Disconnecting one is just `destroy`; the others and `User` itself are untouched. `has_many … dependent: :destroy` removes them all with the account.
- **It has room to grow** for the import step: `last_imported_at`, import progress, and possibly a community to post to. All of that is per Dreamwidth account.

Shape:

```
Journal::DreamwidthAccount
  user_id            (FK)
  username           (string, the Dreamwidth username; stored lowercase, as Dreamwidth treats it)
  api_key            (text, encrypted)
  api_key_digest     (string, SHA-256 of the key, for spotting duplicates)
  verified_at        (datetime, last time Dreamwidth accepted the key)
  timestamps

  unique index on (user_id, username)
  unique index on (user_id, api_key_digest)
```

**Why a digest:** encrypted values can't be searched, so on its own `api_key` couldn't tell us "you've already added this key". A SHA-256 of the key can. Dreamwidth keys are long and random, so the digest can't be turned back into the key.

`User has_many :dreamwidth_accounts, class_name: "Journal::DreamwidthAccount", dependent: :destroy`.

- **Unique per plural-profiles account, not site-wide.** Connecting the same Dreamwidth username twice in one account makes no sense. But two plural-profiles accounts both connecting the same journal is legitimate (a shared household journal, say), and refusing it would tell one account that the other exists.
- **No limit on how many** in v1. Each is a single small row.
- **Linking a connection to a profile or group** (so each journal shows that profile's avatar and name) is a natural extension. It also points towards the native journal posting *as* a profile. It isn't needed for v1, and can be added as a nullable `postable` reference later, the same way chat does it.

### Encryption: Active Record encryption, which isn't set up yet

`encrypts :api_key` is a one-liner, but nothing in the app uses Active Record encryption today, so Phase 0 has to set it up:

- Run `bin/rails db:encryption:init` and put the three keys (`primary_key`, `deterministic_key`, `key_derivation_salt`) in `config/credentials.yml.enc`. Production already decrypts credentials via `RAILS_MASTER_KEY` on Scalingo, so there's no new environment variable. Check that the variable is actually set before relying on it.
- Fixed, non-secret keys for the test environment go in `config/environments/test.rb`, so CI doesn't need the master key.
- Non-deterministic encryption. We never look the key up by value.
- **Losing the encryption keys makes every stored API key unreadable.** That's recoverable (people paste their key in again), but it should be written down next to the master key.

### Never shown back, never logged

- After saving, the settings page shows only that a key is connected, its last four characters and when it was last verified, never the key itself. The form's key field is always empty. You replace a key rather than edit it.
- `filter_parameter_logging.rb` already filters anything matching `_key`, so `api_key` is covered. The client sends the key only in the `Authorization` header and never puts it in a URL.

---

## Talking to Dreamwidth: `Dreamwidth::Client`

A plain Ruby class (`lib/dreamwidth/client.rb`, or `app/models/dreamwidth/client.rb` if we'd rather it autoload). It knows nothing about controllers or plural-profiles models, so the future importer can reuse it as is.

- Built with `Dreamwidth::Client.new(username:, api_key:)`.
- Methods: `entries(count:, offset:)`, `entry(id)`, `create_entry(attrs)`, `update_entry(id, attrs)`, `verify!`. Each returns plain Ruby hashes or small value objects, never raw JSON.
- **Uses `Net::HTTP` from the standard library, with no new gem.** Nothing in the app makes outbound HTTP calls today, and four endpoints don't justify Faraday.
- **Short timeouts** (around 5 s to open, 15 s to read). A slow Dreamwidth must not hold a Puma thread for long. The app is memory-constrained on Scalingo (see `plan-chat-servers.md`), so we can't spare threads.
- **Errors are mapped to a few kinds the controller can phrase kindly:**
  - rejected key (401/403)
  - not found (404)
  - Dreamwidth unavailable (timeouts, 5xx, 429)
  - validation error (Dreamwidth's message passed through)
- Only ever talks to `https://www.dreamwidth.org/api/v1/`. The host is a constant, never taken from input.

`Journal::ApplicationController` looks up the connection from the URL, always through `Current.user.dreamwidth_accounts.find_by!(username: params[:dreamwidth_username])`. Scoping it to the person's own connections means a changed URL can never reach someone else's key: it's a 404. `#dreamwidth_client` then builds the client from that connection. Tests swap that method for a fake (see Testing), so there's no need for WebMock.

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

| Page                | Route                                                                                                         | What it does                                                                                                                                                                                                                                                                                                                                                   |
| ------------------- | ------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Journals            | `GET /journal`                                                                                                | The landing page: a list of your connected Dreamwidth accounts, each linking to its Entries page, plus **Connect another Dreamwidth account**. With no connections, it explains what this is and links straight to Connect. With exactly one, it still shows the list rather than redirecting, so the page stays the same whether you have one journal or six. |
| Connect             | `GET /journal/dw/new`, `POST /journal/dw`                                                                     | Dreamwidth username and API key, with a link to get the key (see "Connecting a journal" below). Saving checks the key with Dreamwidth before storing it.                                                                                                                                                                                                       |
| Manage a connection | `GET/PATCH /journal/dw/:dreamwidth_username/connection`, `DELETE` the same                                    | Shows that the connection exists (last four characters of the key, when it was last verified). It lets you replace the key, or disconnect, with a note that you can also revoke the key on Dreamwidth.                                                                                                                                                         |
| Entries             | `GET /journal/dw/:dreamwidth_username`                                                                        | That journal's recent entries, newest first. Each shows its subject ("(no subject)" if blank), date, security level, an **Edit** link and a **View on Dreamwidth** link. A **Write a new entry** link sits at the top. Plain "Older entries" / "Newer entries" links page through using `offset`.                                                              |
| Write               | `GET /journal/dw/:dreamwidth_username/entries/new`, `POST /journal/dw/:dreamwidth_username/entries`           | Subject, entry text (a large `textarea`, sized in `rem`), security (public / access-locked / private) and tags (one comma-separated text field). After posting, it goes back to that journal's Entries with a notice linking to the new entry on Dreamwidth.                                                                                                   |
| Edit                | `GET /journal/dw/:dreamwidth_username/entries/:id/edit`, `PATCH /journal/dw/:dreamwidth_username/entries/:id` | The same form, filled with the entry's current values.                                                                                                                                                                                                                                                                                                         |

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

### Editing mustn't quietly change what isn't shown

The form shows only some of an entry's settings. Editing must never reset the rest: custom access filters, mood, icon, comment settings, backdating and so on.

- Send **only the fields the form shows** on update. The spec marks every update field as optional, which suggests a partial update, but **this must be verified with a real key** before building Edit (see Phase 0).
- If an entry's security is something the form can't show (for example a custom access filter), the form says so ("This entry is shown to a custom access filter. Saving won't change that.") and leaves security out of the update entirely, rather than squashing it to one of the three options.
- Edit must load the entry's **raw source text**, not rendered HTML. Otherwise a single save would convert someone's markup or formatting. Also verify with a real key (likely `full=1` on the entries endpoint, or the single-entry endpoint).

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
  - edit, keeping fields that aren't shown
  - a failed post that keeps the text
  - a timeout message
  - forced colours, using the existing `with_forced_colors`
  - the accessibility cases the people using this give us
- **Fixtures:** a `journal/dreamwidth_accounts.yml` fixture with fake keys, including one person with two connections and a second person connected to the same Dreamwidth username. These need the test encryption keys above to load.

---

## Phased build order

**Phase 0: check the API with a real key (no code).** Make an API key on Dreamwidth and use `curl` to confirm:

1. `/api/getkey` and the `accesslists` ownership check behave as the source code suggests
2. what the entries list returns: field names, date format and how security is reported
3. how to get an entry's raw text for editing
4. that an update with only some fields leaves the others alone, custom security included

Write the answers into this document. Several decisions above depend on them.

**Phase 1: groundwork and connecting.**
- `/journal` routes and the "Journal" nav link.
- Active Record encryption keys.
- `Journal::DreamwidthAccount`, with as many per account as people like.
- `Dreamwidth::Client` with `verify!` and `entries`.
- The Journals landing page, Connect, Manage a connection, the "Your journals" switcher and the Entries list (read-only).

Ship it. This is already useful for checking things look and read right with real themes and real assistive technology.

**Phase 2: writing and editing.** `create_entry` / `update_entry`, the Write and Edit pages, keeping the text when a post fails, the partial-update rule, and rate limits. After this, people can stop using Dreamwidth's own pages for everyday posting.

**Later, each with its own planning pass:**
- **Native journal.** Entries stored in plural-profiles, posted *as* a profile or group (the same "postable" idea chat already uses), with their own privacy rules. This is where the journal gets properly plural.
- **Import from Dreamwidth.** Uses `Dreamwidth::Client#entries` to page through everything. Probably a Solid Queue job, since it's long-running.
- **Cross-posting.** Write natively, optionally send to Dreamwidth too.
- **Extra Dreamwidth fields.** Icons (`/users/{u}/icons`), mood/music/location, communities and backdating, added as people ask for them.

---

## Open questions

- **Which accessibility needs, specifically, does Dreamwidth's new version break?** This decides what we test for, and might change the form layout.
- **Who can see the Journal at first?** Everyone who's signed in, or only admins until Phase 2 is done? The nav link could stay hidden until then.
