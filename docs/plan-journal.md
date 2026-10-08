# Plan: Journal, starting as an accessible Dreamwidth client

## Summary

Dreamwidth is replacing its page for posting and editing entries with a new version that breaks accessibility needs some of our people rely on. The current posting page works for them; the new one won't. The rest of Dreamwidth is fine: it's still where they read entries. This plan adds a Journal section (`/journal`) to plural-profiles that lets someone list, write and edit their Dreamwidth entries through plain, server-rendered HTML forms, wearing the plural-profiles theme they already use.

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
  communities        (jsonb, default [], community usernames this connection has posted to)
  timestamps

  unique index on (user_id, username)
  unique index on (user_id, api_key_digest)
```

**Usernames are normalised before saving and before every lookup:** lowercased, with hyphens turned into underscores. Dreamwidth treats `foo-bar` and `foo_bar` as the same account, and its API only accepts `[0-9A-Za-z_]`. Normalising means the unique index really does stop the same journal being connected twice, and the URL has only one form.

**Why a digest:** encrypted values can't be searched, so on its own `api_key` couldn't tell us "you've already added this key". A digest can. It's an HMAC keyed from `secret_key_base` (via `Rails.application.key_generator`), not a bare SHA-256, so someone holding a copy of the database can't check it against a key they already have.

**When a key stops working.** If someone revokes their key on Dreamwidth, calls start getting 401s. The client reports this as a rejected key, and the controller sets `failed_at`. Every page for that journal then says plainly that Dreamwidth stopped accepting the key, and links to Manage. There they can replace the key (which clears `failed_at` and sets `verified_at`) or disconnect it and add it again. A later successful call also clears `failed_at`.

**Remembering communities.** Dreamwidth's API can post to a community with your own key, but it can't list which communities you're allowed to post to. So the Write page's "Post to" field offers the communities this connection has successfully posted to before, plus a way to type a new one. A community is added to `communities` (normalised like usernames) after its first successful post, and can be removed from the Manage page.

`User has_many :dreamwidth_connections, class_name: "Journal::DreamwidthConnection", dependent: :destroy`.

- **Unique per plural-profiles account, not site-wide.** Connecting the same Dreamwidth username twice in one account makes no sense. But two plural-profiles accounts both connecting the same journal is legitimate (a shared household journal, say), and refusing it would tell one account that the other exists.
- **No limit on how many** in v1. Each is a single small row.
- **Linking a connection to a profile or group** (so each journal shows that profile's avatar and name) is a natural extension. It also points towards the native journal posting *as* a profile. It isn't needed for v1, and can be added as a nullable `postable` reference later, the same way chat does it.

### Encryption: Active Record encryption, from environment variables

`encrypts :api_key` is a one-liner, but nothing in the app used Active Record encryption before, so Phase 1 sets it up. Like the rest of production's settings (S3, mail and so on), the keys come from **environment variables**, not `config/credentials.yml.enc`, so no master key is involved:

- **Production** reads `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` and `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` (`config/environments/production.rb`). Generate the values with `bin/rails db:encryption:init` (which only prints them) and set them on Scalingo **before anyone connects a journal**. The third key it prints, `deterministic_key`, isn't needed: we never look a key up by value.
- **Development and test** use fixed, non-secret keys in their environment files, so nothing needs setting up locally or in CI. Test also sets `encrypt_fixtures`, so fixture keys are encrypted as they load.
- **Losing the production values makes every stored API key unreadable.** That's recoverable (people paste their keys in again), but keep them somewhere safe.

### Never shown back, never logged

- After saving, the settings page shows only that a key is connected, its last four characters and when it was last verified, never the key itself. The form's key field is always empty. You replace a key rather than edit it.
- `filter_parameter_logging.rb` already filters anything matching `_key`, so `api_key` is covered. The client sends the key only in the `Authorization` header and never puts it in a URL.

---

## Talking to Dreamwidth: `Dreamwidth::Client`

A plain Ruby class in `app/services/dreamwidth/client.rb`, so it autoloads. It's the first file in `app/services/`. It knows nothing about controllers or plural-profiles models, so the future importer can reuse it as is.

- Built with `Dreamwidth::Client.new(username:, api_key:)`.
- Methods: `entries(count:, offset:, security: nil)`, `entry(id)`, `create_entry(attrs)`, `update_entry(id, attrs)`, `tags`, `icons`, `access_lists`, `verify!`. Each returns plain Ruby hashes or small value objects, never raw JSON.
- **What the API actually does** (checked in Phase 0; see "Phase 0 findings" below):
  - Entry IDs are Dreamwidth's public `ditemid`, the number in `/29492.html`. One ID works for list, read, edit and the "View on Dreamwidth" link.
  - Editing is `POST /journals/{u}/entries/{id}`, not `PATCH`. Once #3693 is live, fields left out of an edit keep their current values, `text` is optional, and `datetime` is honoured.
  - Tags go in as a JSON array and come back as one.
  - `datetime` comes back as `"YYYY-MM-DD HH:MM:SS"` in the journal's own time, with no time zone.
  - Creating accepts an `icon` keyword and a `datetime` (`"YYYY-MM-DD hh:mm"`), and both are applied. Icons come from `GET /users/{u}/icons`, each with `keywords`, `url`, `picid` and `comment`.
  - Posting to a community is the same create call with the community's name in the path, using your own key.
  - **Security can't be `custom` yet**: the API rejects it. See "Upstream fixes".
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

**Journal-only styles live in their own `app/assets/stylesheets/journal.css`**, loaded only by journal pages, so it can be handed to people who know some CSS without the whole of `application.css`. It starts with a short note on the site's rules (theme variables, `rem`, forced colours).

### Which journal you're in lives in the URL

Every entries page sits under the Dreamwidth username it works on: `/journal/dw/:dreamwidth_username/entries/new`. Switching journals means following a link to another journal's pages. We considered remembering a "current account" in the session or a cookie instead, and decided against it:

- **No hidden state, so no posting to the wrong journal.** With a remembered "current" account, a second tab could switch it, and a form opened before the switch would post somewhere other than the page said. With the username in the URL, the form posts exactly where its page says, always.
- **Bookmarks and the back button just work**, and each journal's pages can be kept open side by side.
- **It costs nothing extra.** It's one route scope and one `find_by!`.

The `dw/` prefix leaves room for native journal pages to sit beside these later, and for other services in theory.

### The pages

| Page                | Route                                                                                                         | What it does                                                                                                                                                                                                                                                                                                                                                   |
| ------------------- | ------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Journals            | `GET /journal`                                                                                                | The landing page, headed "Your journals": a list of your connected Dreamwidth accounts, each linking to its Entries page, plus **Connect another Dreamwidth account**. With no connections, it explains what this is and links straight to Connect. With exactly one, it still shows the list rather than redirecting, so the page stays the same whether you have one journal or six. |
| Connect             | `GET /journal/connect`, `POST /journal/connect`                                                               | Dreamwidth username and API key, with a link to get the key (see "Connecting a journal" below). Saving checks the key with Dreamwidth before storing it. It isn't under `dw/`, so a Dreamwidth user called `new` can't clash with it.                                                                                                                          |
| Manage a connection | `GET/PATCH /journal/dw/:dreamwidth_username/connection`, `DELETE` the same                                    | Shows that the connection exists (last four characters of the key, when it was last verified, and when Dreamwidth stopped accepting it if `failed_at` is set). It lets you replace the key, or disconnect, with a note that you can also revoke the key on Dreamwidth.                                                                                         |
| Entries             | `GET /journal/dw/:dreamwidth_username`                                                                        | That journal's recent entries, newest first. Each shows its subject ("(no subject)" if blank), date, security level, an **Edit** link and a **View on Dreamwidth** link. A **Post an entry** button sits at the top, with **Back to your journals** beside it. "< Older entries" (left) and "Newer entries >" (right) page through using `offset`, 10 at a time. Dreamwidth doesn't say how many entries there are, so there are no page numbers. In private-only mode, it lists private entries only.         |
| Write               | `GET /journal/dw/:dreamwidth_username/entries/new`, `POST /journal/dw/:dreamwidth_username`                   | Laid out as in "The Write page" below: icon, post as, post to, date and time, subject, entry text, tags, "Show this entry to" with custom filters, and the "Post to: *username*" button. After posting, it goes to that entry's page (below).                                                                                                                  |
| Entry               | `GET /journal/dw/:dreamwidth_username/entries/:id`                                                            | Where Write and Edit land: "Your entry has been posted." or "Journal entry was edited." (from the flash), who can see it, its subject, and what to do next. See "After posting or saving".                                                                                                                                                                     |
| Edit                | `GET /journal/dw/:dreamwidth_username/entries/:id/edit`, `PATCH /journal/dw/:dreamwidth_username/entries/:id` | The same form, filled with the entry's current values, as in "The Edit page" below. Our route is `PATCH`; the client sends Dreamwidth a `POST`. After saving, it goes to that entry's page. See "Editing mustn't quietly change what isn't shown".                                                                                                             |

### Connecting a journal

Dreamwidth has a page, `https://www.dreamwidth.org/api/getkey`, that shows the logged-in account's API key as plain text, and nothing else. If the account has no key yet, it creates one. If nobody is logged in, Dreamwidth asks you to log in and then brings you back to it. (Found in Dreamwidth's source, `DW::Controller::API::REST#key_handler`.) So nobody has to find a key in their settings. The Connect page says:

1. Log in to Dreamwidth as the account you want to connect.
2. **Get your key from Dreamwidth (opens in a new tab).** This link has `target="_blank"` and `rel="noopener"`. The "(opens in a new tab)" is part of the visible link text, so nobody is surprised by it.
3. Copy the key that page shows, then come back to this tab and paste it below.

It also notes, briefly, that the key lets plural-profiles read and post to that journal, and that it can be revoked in Dreamwidth's mobile settings (`/manage/settings/?cat=mobile`).

**Checking what was pasted.** It's easy to be logged in to Dreamwidth as a different account from the one you meant, so saving runs three checks, in this order, each with a plain message that says what to do:

| Check                           | How                                                        | Message                                                                                                                                                                                                                                                                             |
| ------------------------------- | ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Already connected this journal? | `username` matches another of your connections             | "You've already connected *username*." with a link to its Manage page, to replace the key there.                                                                                                                                                                                    |
| Already added this key?         | `api_key_digest` matches another of your connections       | "You've already added this key: it's the one for *otheruser*. Dreamwidth gives each account its own key, so you were probably logged in to Dreamwidth as *otheruser*. Log out of Dreamwidth, log in as *username*, then get the key again."                                         |
| Is it this journal's key?       | `GET /api/v1/journals/{username}/accesslists` with the key | 200 → save. 403 → "That key belongs to a different Dreamwidth account than *username*. Check which account you're logged in to on Dreamwidth." 404 → "Dreamwidth doesn't have an account called *username*." 401 → "Dreamwidth didn't accept that key. Check you copied all of it." |

Already connected comes first, so pasting the same journal's key again says "already connected" rather than "you were probably logged in as *username*". The first two checks don't ask Dreamwidth at all, and the username's format is checked before it's sent anywhere.

The `accesslists` call is a reliable ownership check because Dreamwidth answers 403 unless the key's owner *is* `{username}` (`DW::Controller::API::REST::Journals#accesslists_get`). It's also read-only and harmless. The entries endpoints aren't good enough for this: they'd happily list someone else's public entries.

On any failure the form keeps the username, and empties the key field so the next paste doesn't get mixed with the old one.

### Switching journals

- **Every page shows the journal it's for, in the `h1` itself:**
  - Entries: "*username*'s entries"
  - Write: "Post an entry", Dreamwidth's wording in pp's sentence case. The journal is right below, in "Post as" and "Post to", and on the button.
  - Edit: "Editing an entry in *username*"

  It's the first thing a screen reader announces and the first thing anyone sees, so nobody has to wonder whose journal they're about to post to.
- **The Write form repeats where it's posting on the submit button itself** ("Post to: *username*", or "Post to: *community*"), as Dreamwidth's does. It's the last thing read before acting.
- **A short "Your journals" `nav` near the top of every journal page** lists each connected account as a link to its Entries page. The current one is marked with `aria-current="page"`, which also has a visible style. It's an ordinary list of links (no dropdown, no JavaScript), so it works the same everywhere. With only one connection it can be left out.
- **The entry page after posting names the journal too**, with a link to it, as confirmation.

**Linking to a journal.** Wherever a journal is named (Poster, the entry page, "Your journals"), it's shown the way Dreamwidth shows it: Dreamwidth's small "userhead" icon (a person, or a globe for a community: our own copies in `app/assets/images/dreamwidth/`, from the Silk icon set under CC BY 2.5 and credited in the README, rather than hotlinked from Dreamwidth), then the username in bold, linking to the journal on Dreamwidth. The people this is for asked for this; it replaces the link to their journal in Dreamwidth's header, which they liked. Journal addresses use hyphens where usernames have underscores (`foo_bar` → `https://foo-bar.dreamwidth.org/`). One helper builds it. Once we can tell which icon is the default (see "Upstream fixes"), the journal's default icon can sit beside it too. Like every link to Dreamwidth, it opens in a new tab, since it leaves Plural Profiles: marked with ↗ (as the site's other new-tab links are) and "(opens in a new tab)" for screen readers. Dreamwidth itself isn't a problem for the people using this (only its new posting page is), so linking out to read entries there is fine.

**Not in v1.** The people this is for said they're fine without these from Dreamwidth's pages:

- choose a random icon, the help and FAQ links ("Supported HTML" and so on)
- the Rich Text / HTML tabs and "Disable Auto-Formatting"
- mood, location, music, comment settings, comment screening, age restriction and its reason, crossposting
- Dreamwidth's header and footer
- Delete Entry (the API can't delete anyway), "Add to memories", and a separate tags-only editing page (the Edit page has the tags field)

We're also leaving out Preview; Spell check (the browser's own spell checking already works in the text box, and they use it); Update Date (the date fields are always shown and filled in); "Insert Image" and "Embed Media"; and "Don't show on Reading pages" (which the API can't set anyway).

### The Write page

The people this is for sent screenshots of Dreamwidth's posting page, and told us what they value about it. The Write page follows it closely.

**What they value:**

- **Focused:** everything sits in one central column, with empty space either side and no sidebar. The main layout already does this. Their focus starts at the form, so there's little above it: the site header, then a one-line `h1`.
- **Plural-profiles' own style, as much as possible.** They like how plural-profiles looks and works, and especially how it works with Firefox's forced colours. So Write and Edit are built from the same pieces as the rest of the site: **a pane (`.card`) with a pane header (`.card__header`)**, the usual form, label and button styles, and each person's theme. What we take from Dreamwidth is the **order** of things and its **wording**, not its look.
- **One pane for the whole form.** Its header is the page's `h1` ("Post an entry"). It was first planned as four panes (details, entry, tags, who can see it), but seen in use it all belongs together.
- **The order of things**, top to bottom:
  1. The chosen icon's image at top left. Beside it (or below it on narrow screens): **Post as** the journal (see "Linking to a journal"), **Post to** a dropdown of the journal and remembered communities, **Date** the date fields, **Icon** the icon dropdown.
  2. **Subject**, then the large entry text box, then the draft status ("Autosaved draft at 20:22").
  3. **Tags**, one comma-separated field, with tag suggestions.
  4. **Show this entry to** dropdown, then the custom filter checkboxes, then the **Post to: *username*** button.

**Details:**

- **Labels use Dreamwidth's wording, without its colons** (pp's labels don't have them): "Post as", "Post to", "Date", "Icon", "Subject", "Entry text", "Tags", "Show this entry to". The dropdown options are "Everyone (Public)", "Access List", "Private (Just You)" and "Custom Filter", sent as `public`, `access`, `private` and `custom`.
- **The entry text is a large `textarea` in the site's usual font**, the same as plural-profiles' description boxes (which moved from monospace to the default font a while ago, without complaint). About 25 lines tall, sized in `rem` so it grows with text size, and resizable vertically. Dreamwidth's is monospace; we can switch if they'd prefer it.
- **Date fields are always visible**, rather than behind an "Edit Date" link (the people using it suggested this). They reuse the existing `shared/_datetime_picker` partial, which already matches Dreamwidth's: month, day, year, hour : minute, "(24 hour time)", with visually hidden labels, and no JavaScript needed. They're filled in with now, in the person's time zone. **If they're not changed, `datetime` is sent as the moment of posting, in the person's time zone**, so a page left open for an hour still posts at the right time. (Left out, Dreamwidth dates the entry in UTC, not the journal's time.) A hidden field holds the original value to compare against.
- **Icon:** a dropdown of icon keywords, "(default)" first. The image at top left shows the chosen icon. Without JavaScript it shows the icon last submitted (or the default); with JavaScript it updates as the choice changes. Images load straight from Dreamwidth (`url` from the icons list). Which icon is the default isn't in the API yet (see "Upstream fixes"); until it is, we take it from the newest entry Dreamwidth reports with `icon_keyword` "(default)", and show no image if there isn't one.
- **Custom filters:**
  - **Essential.** Almost all their entries use them. Write can be built without them, but people can't start using it until Dreamwidth accepts custom security (#3688).
  - **More than one can be ticked**; the entry is shown to anyone in any ticked filter. Sent as a list of filter ids (from `accesslists`).
  - **Without JavaScript, the list is always visible.** With JavaScript, it appears when "Custom Filter" is chosen. The people using it are happy with either.
  - **Laid out in columns that fill down, then across**, as Dreamwidth's does for long lists (CSS `columns`), dropping to one column on narrow screens. Reading and Tab order follow the same order.
  - **The ticked state must be obvious** in every theme and in forced colours.
  - **Order:** whatever order Dreamwidth's page uses. To check against the real page once it's built.
  - **Safety:** with JavaScript, ticking a filter switches the dropdown to "Custom Filter". On the server, if any filters are ticked but the dropdown isn't "Custom Filter", nothing is posted: the form comes back with everything kept and "You ticked some filters, but 'Show this entry to' is set to *Everyone (Public)*. Choose 'Custom Filter' to use them, or untick them." We never guess which they meant, since a wrong guess shows an entry to the wrong people.
- **Narrow screens:** the same order, stacked in one column.

### The Edit page

The same form and layout as Write, filled with the entry's current values, as on Dreamwidth's edit page. The differences, again following Dreamwidth:

- **"Poster"** (the journal, as a link) instead of "Post as", and **no "Post to"**, since an entry can't move to another journal.
- **The button says "Save".** The journal is already named in the `h1`.
- **No Delete Entry button.**
- **The entry's custom filters come back ticked.** Until #3688, they're listed as text instead (see "Editing mustn't quietly change what isn't shown").
- Unlike Dreamwidth's edit page, ours keeps an `h1` ("Editing an entry in *username*") and the same centred column as Write, so the two pages match and screen readers announce where they are.

### Tag suggestions

The people using it liked one thing about Dreamwidth's new posting page: typing in the tags field lists **every** matching tag, where the old page suggested only one. They'd like it to work like chat's emote autocomplete, but starting after one character.

- **The journal's tags come from `GET /journals/{u}/tags`**, which works today (it's separate from the bug about saving tags on edit). It returns each tag's name, sorted. They're fetched with the page and embedded as JSON, so suggestions appear instantly while typing.
- **A Stimulus controller, following `emote_input_controller.js`**: a combobox with a listbox of options, Up/Down to move, Enter or Tab to choose, Escape to close, and a polite live announcement of how many tags match. Any listbox code worth sharing with the emote controller can be pulled out as we go, rather than up front.
- **It works on the tag being typed**: the text after the last comma. It opens after **one character**.
- **Matching** ignores case, and treats every character literally (some of their tags start with `*`, so `*m` finds `*mood`). **Only tags that start with what's typed** are listed. Matching anywhere in the tag was tried first, but with a lot of tags it was more surprising than useful. Tags already in the field are left out. Every match is listed, scrolling if there are many.
- **Choosing a tag** replaces what's being typed with the tag, followed by ", ", ready for the next one.
- **The list opens below the field**, not at the caret, since it's a single-line field.
- **Each tag can be at most 40 characters** (Dreamwidth's limit). We check that before posting, and if one is too long, the form comes back with everything kept and says which tag is too long.
- **Not for now**: a "browse all tags" button, and showing how often each tag has been used. The API gives usage counts, so either can be added later.
- Without JavaScript, or if Dreamwidth doesn't answer for the tags, it's the plain comma-separated field.

### After posting or saving: the entry page

Dreamwidth shows a confirmation page after posting or editing, and the people using it rely on what's on it. Ours is `GET /journal/dw/:dreamwidth_username/entries/:id`, which Write and Edit both redirect to:

- **First line**, from the flash: "Your entry has been posted." or "Journal entry was edited." Visiting the page again later shows the rest without it.
- **Who can see it:** "The entry is visible to your custom access filter(s) *filter*, *filter*." (or Everyone, Access List, Private). And the subject: "The entry was posted with the following subject: *subject*" or "(no subject)".
- **Both are read back from Dreamwidth**, not echoed from what we sent, so if Dreamwidth saved something different, this is where it shows. Filter names come from `accesslists`.
- **"From here you can:"**
  - View this entry (on Dreamwidth)
  - Edit this entry (our Edit page; "Edit this entry again" after an edit)
  - View *username*'s journal (on Dreamwidth)
  - Back to *username*'s entries (our Entries page)
  - Post another entry (after posting)
- **It clears the draft** for that form (see "Never lose someone's writing").

### Never lose someone's writing

This is the most important behaviour, and the reason for the rule below.

- **If Dreamwidth rejects or fails a post or edit, re-render the form with everything the person typed still in it.** Don't redirect. Show the error at the top of the form, as text, saying what happened and whether trying again might help.
- After a timeout we can't know whether the entry was actually saved. The message must say that and suggest checking the Entries page before trying again, so nobody ends up with a duplicate post.
- Protect against double-submits with `data-turbo-submits-with` on the submit button. It only works with Turbo, but a double post is annoying rather than harmful.

**Drafts, saved in the browser.** Dreamwidth autosaves drafts and shows "Autosaved draft at 8:22:18 PM" under the text box, and the people using it want that. They write on one device, so drafts stay **in the browser on that device** (`localStorage`), never on our server. That keeps their unposted, mostly filter-locked writing off plural-profiles entirely.

- A Stimulus controller saves the whole form (subject, text, tags, icon, date, security, filters) two seconds after typing stops, immediately on **Ctrl+S** (or Cmd+S), which it takes over from the browser's "Save page", and on leaving the page. A form with no subject, text or tags removes the draft rather than saving an empty one.
- **"Autosaved draft at 20:22:18"** (Dreamwidth's wording, with seconds so it's clear it keeps updating, in 24-hour time) appears just below the text box, after Ctrl+S too. It's only announced to screen readers after Ctrl+S (a polite live region updated then), not every few seconds, so it doesn't keep interrupting.
- There's one draft per connection for Write, and one per entry for Edit. Keys are `journal-draft:<user id>:<connection id>:new` (`journal_drafts.js`, following `chat_drafts.js`), so another account in the same browser never sees them, and **signing out clears the account's journal drafts**, as it does chat drafts.
- Coming back to a form with a draft offers: "You have an unsent draft from 20:22. **Restore it** / **Discard it**". It never restores silently over what's on the page. Until one is chosen, nothing is saved (the status line says so), so typing can't overwrite the draft by accident. A form that came back from a failed post already has the writing in it, so isn't offered one.
- **The date is only restored if it had been changed.** Otherwise the restored entry is dated when it's posted, like any other.
- The entry page clears the draft after a successful post or save: posting puts the draft's key in the flash, and the next page clears it.
- **The Write page opts out of Turbo's cache.** Otherwise coming back flashes up a snapshot of what was typed, then the fresh form replaces it, which looks like the writing appearing and vanishing.
- Without JavaScript, the form works as before, just without drafts.

### Private-only mode, until Dreamwidth's fixes are deployed

Dreamwidth has merged fixes for reading access-locked entries (#3687), tags on edit (#3691), and edits resetting settings they didn't mention (#3693). They aren't deployed yet. Rather than build workarounds for bugs that are about to go away, we build for the fixed API and start with a **private-only mode**, which is one switch (a constant such as `Journal::PRIVATE_ONLY`). While it's on:

- **Entries lists private entries only** (`security=private`), with the normal "Older entries" / "Newer entries" paging. Private entries are the one kind that both reads and lists correctly today, and a single filter pages properly.
- **Write always posts as private.** "Show this entry to" shows just "Private (Just You)", with a short note that more options are coming. "Post to" is a dropdown with only the connected journal in it (not sent with the form), with a note that communities will come later, so it's clear where they'll be. Subject, text, tags, icon and date all work today when creating.
- **Edit sends only `subject` and `text`.** It doesn't touch any other field. Until #3693 is live, though, Dreamwidth's old edit code resets some settings whatever we send: it removes an entry's tags, puts comment settings and age restriction back to the journal default, and unticks "Don't show on Reading pages". **So in this mode, only edit private test entries.** The Edit page says so.

**Turning it off.** When this prints "…Fields left out of the request keep their current values.", all three fixes are live:

```sh
curl -s https://www.dreamwidth.org/api/v1/spec | jq -r '.paths["/journals/{username}/entries/{entry_id}"].post.description'
```

Then check it with a real key (read an access-locked entry; edit a test entry's tags), and turn the switch off. Entries then lists everything; Write offers public, access-locked and private, plus communities; Edit sends all its fields. Custom filters follow once #3688 is fixed.

### Editing mustn't quietly change what isn't shown

The form shows only some of an entry's settings. Editing must never reset the rest: mood, comment settings, age restriction, backdating, custom access filters and so on.

Phase 0 found that Dreamwidth's edit endpoint reset several of these (see "Phase 0 findings"). That's fixed by #3693: **fields left out of an edit keep their current values.** So once it's live:

- **The client sends only what the form shows:** `subject`, `text`, `tags`, `icon`, `datetime`, and `security`. Nothing else, so everything else is kept.
- **Custom-filtered entries leave `security` out** until Dreamwidth accepts `"custom"` (#3688). That keeps their filters as they are. Their Edit page shows the filters as text ("Shown to: Close friends, Family") with a note that changing them here isn't possible yet. Once #3688 is fixed, the filters become checkboxes like on Write, and Edit sends them.
- **The date can be changed** on Edit, as #3693 makes the edit endpoint honour `datetime`.
- Edit loads the entry's **raw source text** (`body_raw` and `subject_raw`, which Dreamwidth includes when the key can edit the entry), not the rendered `body`. Otherwise a single save would convert someone's markup or formatting. (`full=1` is in the spec but does nothing.)

### Entry text is never rendered as HTML here

Entry bodies only ever go into a `textarea`, which HAML escapes. Subjects are shown as escaped text. We never pass Dreamwidth content through `formatted_description` or `html_safe`. That removes any chance of cross-site scripting through someone's own entries, and means there's nothing to sanitise.

### Accessibility

This is the whole reason the feature exists, so it gets more attention than usual, on top of the existing checklist in `.github/copilot-instructions.md`:

- Every field has a visible `label`. Hints and errors are tied to their field with `aria-describedby`.
- "Show this entry to" is a labelled `select`, as on Dreamwidth's page, because that's what the people using it asked for. (An earlier draft used radio buttons.) The custom filter checkboxes sit in a `fieldset` with a `legend`, and their ticked state is obvious in every theme and in forced colours.
- The date fields are a group with a "Date" legend and a hidden label on each field (as `shared/_datetime_picker` already does).
- The draft status is only announced after Ctrl+S, not on every autosave.
- Errors after a failed submit appear in a summary at the top of the form that lists each problem and links to its field. The summary is the first thing after the `h1`, so it's announced when the page loads.
- Flash notices on journal pages sit directly after the `h1`, rather than above the header, so screen readers reach them in reading order.
- Entries is a real `ol` of links. Each Edit link includes the entry's subject in hidden text ("Edit *Monday thoughts*"), so a list of links read out of context still makes sense.
- Large text, narrow screens and `forced-colors` are checked for every page, as in chat. Forced colours matter especially here: the people using it rely on them in Firefox, and like how plural-profiles already works with them, so journal pages must work just as well.
- **Check dropdowns with them on their Chromebook.** On Dreamwidth, the open dropdown list highlights the current option in white with light text, which makes it unreadable. Plural-profiles' own dropdowns already work for them, so ours should too, but it's worth checking "Show this entry to" and "Icon" specifically.
- **What Dreamwidth's new posting page breaks for them:** it is cluttered, splits the form into separate boxes spread across columns that can't be rearranged or simplified, and moves the Post button to the top, away from the end of the form. The plan avoids all of that (one column, a fixed order, Post last), and browser tests check the order stays that way.

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
  - the Write page's order matches "The Write page", at wide and narrow widths
  - ticked filters with "Show this entry to" not set to "Custom Filter" posts nothing and keeps the form
  - an unchanged date sends now in the person's time zone; a changed one sends what was chosen
  - after posting and after saving, the entry page shows who can see it and the subject, read back from Dreamwidth
  - drafts: typing saves a draft, Ctrl+S saves and announces it, coming back offers to restore, and posting clears it
  - tag suggestions: one character opens the tags starting with it (only those), choosing one adds it with ", ", and tags already in the field aren't offered
  - a tag over 40 characters posts nothing and keeps the form
  - posting to a community adds it to that connection's remembered communities
  - private-only mode: Entries asks for private entries and pages through them; Write offers only Private; Edit sends only `subject` and `text`
  - with the mode off: edit sends exactly `subject`, `text`, `tags`, `icon`, `datetime` and `security`, and leaves `security` out for a custom-filtered entry
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
- The Journals landing page, Connect, Manage a connection (including `failed_at`), the "Your journals" switcher and the Entries list (read-only), in private-only mode.
- Visible to everyone who's signed in, with no admin-only stage.

Ship it. This is already useful for checking things look and read right with real themes and real assistive technology.

**Phase 2: writing and editing.** `create_entry` and `update_entry`; the Write and Edit pages as laid out above (icon chooser, date and time, and, once the mode is off, post to with remembered communities and the full "Show this entry to"); the entry page after posting or saving; drafts; tag suggestions; keeping the text when a post fails; and rate limits. Built in private-only mode, and tested on private test entries.

**Phase 3: everything, once Dreamwidth deploys its fixes.** Turn private-only mode off (see "Private-only mode"). This should be small: the pages are already built for the fixed API.

**Phase 4: custom filters, once #3688 is fixed.** The custom filter checkboxes on Write and Edit. **The people this is for can't start using it until then**, since almost all their entries use custom filters.

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
- Editing returns the same shape. What an edit kept and reset, before #3691 and #3693:

| Setting                                   | When left out of an edit                    | When sent                              |
| ----------------------------------------- | ------------------------------------------- | -------------------------------------- |
| Subject, security (public/access/private) | kept                                        | changed                                |
| Date, mood, music, location, icon, format | kept                                        | changed (date ignored)                 |
| Tags                                      | **all removed**                             | **mangled** into one tag, `array(0x…)` |
| Comments disabled / no email              | **reset to the journal default**            | changed                                |
| Age restriction and reason                | **reset to the journal default**            | changed                                |
| Backdated ("Don't show on Reading pages") | **unticked**                                | not in the API                         |
| Custom access filter                      | **kept as "custom" with no filters ticked** | not in the API                         |
- Tags sent as a string are rejected with a 400, because the request is checked against the spec.
- Creating with `"icon": "<keyword>"` and `"datetime": "2026-10-01 12:00"` applies both (read back as `icon_keyword` and `"2026-10-01 12:00:00"`).
- `"security": "custom"` is rejected with a 400, for the same reason.

**Icons**

- `GET /users/{u}/icons` returns a list of `{keywords, url, picid, comment, username}`.

## Upstream fixes

Dreamwidth's code is open source ([dreamwidth/dreamwidth](https://github.com/dreamwidth/dreamwidth)) and actively maintained. Fixing these upstream helps every API user, not just us.

| Problem                                                                                                             | Status                                                                                                                                                                                                                                                                                 | Unblocks                                                             |
| ------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| Reading access-locked / custom entries returns 500 (`LJ::Entry::TO_JSON`)                                           | Issue [#3686](https://github.com/dreamwidth/dreamwidth/issues/3686), PR [#3687](https://github.com/dreamwidth/dreamwidth/pull/3687): **merged 2026-10-07**, not yet deployed                                                                                                           | Turning off private-only mode                                        |
| Tags sent as a list are mangled on edit                                                                             | Issue [#3689](https://github.com/dreamwidth/dreamwidth/issues/3689), PR [#3691](https://github.com/dreamwidth/dreamwidth/pull/3691): **merged 2026-10-07**, not yet deployed                                                                                                           | Turning off private-only mode                                        |
| Edits reset settings the request didn't include (tags, comments, age restriction, backdating, slug, custom filters) | Issue [#3690](https://github.com/dreamwidth/dreamwidth/issues/3690), fixed by [#3693](https://github.com/dreamwidth/dreamwidth/pull/3693) (zorkian's API test suite and fixes): **merged 2026-10-07**, not yet deployed. #3693 also makes edits honour `datetime` and `text` optional. | Turning off private-only mode                                        |
| The icons list doesn't say which icon is the default                                                                | Issue [#3696](https://github.com/dreamwidth/dreamwidth/issues/3696): **open**                                                                                                                                                                                                          | Showing the default icon reliably on Write and next to journal names |
| Custom security can't be posted (the request schemas only allow `public`/`private`/`access`)                        | Issue [#3688](https://github.com/dreamwidth/dreamwidth/issues/3688): **open**. #3693 fixed the editing half (filters are kept); posting `"custom"` is still rejected. PR once the field name (`custom_groups`) is agreed.                                                              | Phase 4: the people this is for using it                             |

---

## Open questions

None at the moment.
