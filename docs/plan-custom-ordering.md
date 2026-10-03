# Plan: Custom Ordering of Groups and Profiles

## Summary

Let people choose the order their groups and profiles appear in, instead of always alphabetical. The order applies everywhere groups and profiles are listed: the "our" sidebar, public group pages (explorer tree, cards, no-JS fallback), our group pages, and the chat "posting as" pickers.

Profiles can belong to several groups, and the order is per group: a profile can be first in "Partners" and last in "Littles".

Reordering happens in the sidebar. It switches into a reorder mode with drag handles and keyboard-accessible "Move up" and "Move down" buttons.

### Request

> we can't control what order our groups and profiles show in. (sidebar, profile cards on group pages, chat send-message-as picker, etc)
>
> it often makes things uncomfortable or unhelpful, things like... the person whose profile contains the information that you need to read first in order for the rest to make sense being at the bottom, partners being seperated by a bunch of random people who aren't in the relationship, etc.

## Decisions

| Question | Decision |
| --- | --- |
| Groups and profiles mixed together? | No. They stay in two separately ordered blocks: sub-groups first, then profiles. |
| Where do new items go in a custom-ordered list? | At the end. Unpositioned items sort after positioned ones, alphabetically among themselves. |
| How is dragging activated? | A "Reorder" toggle in the sidebar shows drag handles and move buttons. Otherwise links behave as normal. |
| Can dragging move items between groups? | No. Items are reordered within their current list only. Membership changes stay on the manage pages. |
| Is ordering per path or per group? | Per group. A group's contents have the same order wherever that group appears in a tree. Inclusion overrides stay path-scoped, but ordering does not need to be. |
| Reset? | Each list can be reset to A–Z, which clears its positions. |

## Current state

Everything is ordered alphabetically by name, then unlabelled items before labelled ones, then labels. This sort comes from `HasLabels` ([app/models/concerns/has_labels.rb](../app/models/concerns/has_labels.rb)) in two forms:

- `order_by_name_and_labels`, an SQL scope
- `name_and_label_sort_key`, a Ruby sort key used when trees are built in memory

Where ordering happens today:

| List | Location |
| --- | --- |
| Sidebar: top-level groups, child groups, profiles in a group | `SidebarTree#sidebar_tree` and `#build_sidebar_node` ([sidebar_tree.rb](../app/models/concerns/sidebar_tree.rb)) |
| Sidebar: flat "Profiles" list | `SidebarTree#sidebar_tree` (`all_profiles`) |
| Public explorer tree | `Group#descendant_tree` → `#build_tree`; root profiles via `#visible_root_profiles` |
| Public cards panel | `Group#visible_direct_child_groups`, `#profiles_visible_at_path` ([groups_controller.rb](../app/controllers/groups_controller.rb)) |
| Public no-JS fallback | `Group#descendant_tree` (rendered flat in [groups/show.html.haml](../app/views/groups/show.html.haml)) |
| Flat descendant list | `Group#descendant_sections` → `#walk_descendants` |
| Our group page cards | [our/groups/show.html.haml](../app/views/our/groups/show.html.haml) (`child_groups` and `profiles`) |
| Manage profiles / manage groups | [manage_profiles.html.haml](../app/views/our/groups/manage_profiles.html.haml), `Group#management_tree`, `#management_root_profiles` |
| Duplication preview | `Group#build_duplication_preview`, `Our::GroupsController#duplicate_confirm` (uses `.order(:name)`) |
| Chat pickers | [_posting_as_picker.html.haml](../app/views/chat/channels/_posting_as_picker.html.haml), [chat/servers/_form.html.haml](../app/views/chat/servers/_form.html.haml), `Chat::ServersController`, `Chat::MembershipsController` |
| Index pages, search, "groups this profile is in" | `Our::GroupsController#index`, `Our::ProfilesController#index`, `Our::SearchController`, [our/profiles/show.html.haml](../app/views/our/profiles/show.html.haml) |
| Association default | `Group has_many :profiles, -> { order(:name) }` |

Inside a group, child groups always come before profiles: in both sidebars, the public tree, and as two separate card grids on group pages.

## Data model

Each list's order lives in the table that defines membership of that list:

| Column | Orders | Used by |
| --- | --- | --- |
| `group_profiles.position` | Profiles inside a particular group | Sidebar group contents, public tree and cards, our group page, manage profiles |
| `group_groups.position` | Child groups inside a particular parent | Sidebar, public tree and cards, our group page, manage groups |
| `groups.position` | Account-wide group order | Top-level sidebar groups, chat pickers, groups index, "groups this profile is in" |
| `profiles.position` | Account-wide profile order | Sidebar "Profiles" list, chat pickers, profiles index |

The migration notes:

- All columns are `integer`, nullable, with no default.
- No backfill is needed: `NULL` means "not positioned".
- Add a composite index for each link table: `(group_id, position)` and `(parent_group_id, position)`.

### Sort rule

```
ORDER BY <table>.position ASC NULLS LAST, <existing name-and-labels order>
```

This sort rule means:

- Lists nobody has touched remain alphabetical.
- New items in a custom-ordered list appear at the end, alphabetically among other unpositioned items.
- "Reset to A–Z" sets every position in that list to `NULL`.

When a list is saved, every item in it gets a position (0..n-1), so the stored order is fully explicit.

## Model and query changes

### Sorting helpers

A small `Positioned` concern ([positioned.rb](../app/models/concerns/positioned.rb)), included in `Group` and `Profile` alongside `HasLabels`, with:

- `order_by_position_then_name(table = table_name)`: an SQL scope qualifying `position` with the right table. A qualified column is needed because `groups.position` and `group_groups.position` can both be in a joined query.
- `position_sort_key(position)`: a Ruby sort key `[position.nil? ? 1 : 0, position || 0, *name_and_label_sort_key]`, for in-memory tree building.

`order_by_name_and_labels` now qualifies its columns with the table name, so it also works on queries joined to a link table.

`Group` gains three helpers built on these:

- `ordered_profiles`: the group's profiles in its own order (SQL).
- `ordered_child_groups`: the group's child groups in its own order (SQL).
- `ordered_profiles_from_preload`: the same order as `ordered_profiles`, worked out in memory from preloaded `group_profiles: :profile`.

### Association

Remove `-> { order(:name) }` from `Group has_many :profiles`. Preloading a `has_many :through` doesn't reliably apply an order that refers to the link table. Callers should sort explicitly with the new helpers. Check every caller of `group.profiles` (listed above) for its ordering.

### Tree builders

These already load `GroupGroup` edges in one query (`build_children_map`, `all_edges` in `SidebarTree`). Change them as follows:

- Pluck `position` alongside `parent_group_id, child_group_id`, and carry it in the children map entries (`{ id:, position: }`).
- Preload `group_profiles: { profile: ... }` in place of `profiles`, so each link's position comes with its profile, and use `ordered_profiles_from_preload`.
- Replace `.sort_by(&:name_and_label_sort_key)` with `position_sort_key` in each place listed below.

The places to change:

- `SidebarTree#sidebar_tree`: top-level groups by `groups.position`, the flat profiles list by `profiles.position`.
- `SidebarTree#build_sidebar_node`: child groups by edge position, profiles by link position.
- `Group#build_tree`, `#walk_descendants`, `#build_management_tree`, `#build_duplication_preview`.
- `Group#visible_root_profiles`, `#profiles_visible_at_path`, `#management_root_profiles`: join `group_profiles` and order by it.
- `Group#visible_direct_child_groups`: order by `group_groups.position`.
- `Our::GroupsController#duplicate_confirm`: replace `.order(:name)`.
- Views: our/groups/show, manage_profiles, our/profiles/show, chat pickers, index pages.

Search results also switch to the account-wide order, for consistency.

### Duplication

`Group#deep_duplicate` copies `position` when it recreates `GroupGroup` and `GroupProfile` rows, so a duplicated tree keeps its arrangement. Fresh copies of groups and profiles get `position: nil` and land at the end of the account-wide lists.

### Membership changes

No extra work is needed:

- Adding a profile to a group creates a link with `position: nil`, so it shows at the end.
- Removing a link drops its position along with it.

## Saving an order

### Route

```ruby
patch "our/ordering", to: "our/orderings#update", as: :our_ordering
```

### Params

| Param | Meaning |
| --- | --- |
| `list` | Which list is being saved: `profiles` or `groups` (account-wide), `group_profiles` or `group_groups` (inside a group). |
| `group` | The owning group's UUID. Only for `group_profiles` and `group_groups`. |
| `ids` | The items' UUIDs in their new order. |
| `reset` | Optional. `"true"` clears the list's positions (A–Z). |

### Behaviour

- Scope everything through `Current.user`.
- The submitted UUIDs must be exactly the current members of the list, with no extras and no missing items. Otherwise respond `409 Conflict` and write nothing. This guards against stale tabs after membership changes.
- Lock the list's rows, check membership and write all positions in one transaction. The write is a single `UPDATE ... SET position = CASE id WHEN ... END`, built with Arel.
- Respond with a status code only: `204 No Content` when saved, `409` for a stale list, `404` for a group that isn't the user's, `400` for an unknown list.

The logic lives in `ListOrder` ([list_order.rb](../app/models/list_order.rb)); the controller only maps its outcomes to status codes.

### The account-wide group order

The sidebar only shows top-level groups at the top level, so the `groups` list is the user's **top-level** groups.

Saving it also clears any position left on a group that has since been nested inside another. Otherwise, such a group would jump ahead of other nested groups in account-wide lists like the chat pickers. Nested groups therefore follow the positioned top-level groups in those lists, alphabetically.

## Interaction design

### Reorder mode

- The sidebar gets a small "Reorder" button under the search box. Reorder mode is remembered for the tab, in `sessionStorage`, so someone can work through several groups across pages without switching it on each time.
- **In reorder mode:**
  - Each row shows a drag handle (grip icon) and "Move up" / "Move down" buttons with visually hidden labels naming the item, e.g. "Move Alex up".
  - Each group row also has an "A–Z" button, which sorts that group's contents (both blocks) back to alphabetical.
  - "Sort A–Z" buttons for the top-level groups and the flat profiles list appear next to "Expand all / Collapse all".
  - Sorting A–Z asks for confirmation, then reloads the page, since the server owns the alphabetical order (names, then labels).
  - A short hint explains the handles and buttons.
  - Links stay clickable.
  - `<details>` stay open/closable via their arrows. Clicks on the handle and buttons inside a `<summary>` don't open or close it.
  - The toggle reads "Done reordering".
- **Outside reorder mode:** the sidebar looks and behaves exactly as before. The controls are added by the controller when the mode starts, rather than rendered for everyone.

### Dragging

- Use SortableJS, pinned via `bin/importmap pin sortablejs`.
  - It is small and handles touch and mouse.
  - It supports a `handle` option, so only the grip starts a drag. That avoids conflicts with links, `<summary>` toggling and touch scrolling.
- SortableJS runs in its pointer-event mode (`forceFallback`). Native HTML5 drag and drop behaves inconsistently between browsers and doesn't work on touch screens at all.
- Every `<ul>` holding reorderable items is its own Sortable, so items can't leave their `<ul>`.
- A group's child groups and its profiles share one `<ul>`, as before. Each item carries its list (`data-reorder-list` plus `data-reorder-group`), and `onMove` refuses a move past an item from the other list, so the two blocks stay separate.
- A group that appears in several places in the tree is rendered once per place. After a move, every copy of that list is put in the new order.
- On drop, `fetch` PATCH the new order with the CSRF token. On failure:
  - restore the previous DOM order
  - show an error message
  - for a 409, suggest reloading

### Keyboard and screen readers

- "Move up" / "Move down" buttons work without dragging (WCAG 2.5.7 Dragging Movements). They swap the row with its neighbour and save.
- Focus stays on the moved item's button after a move.
- An `aria-live="polite"` region announces "Alex moved to position 2 of 5 in Partners".
- On the first item, "Move up" is unavailable; on the last item, "Move down" is. Both use `aria-disabled` rather than `disabled`, so a button keeps focus when its item reaches the end. Focus then moves to the other button, which can still do something.
- Saves run one at a time, in order. If one fails, the list goes back to its last saved order and a `role="alert"` message explains what happened.
- Handles and buttons are sized in rem: 24px at the default text size, and larger with larger text.
  - In a narrow sidebar with large text, the buttons wrap onto their own line, rather than squeezing names until they break mid-word.
- They look correct in forced-colors mode, using `btn--secondary`. Unavailable buttons show in `GrayText`.

### No-JS fallback

- The reorder toggle is gated behind `.js`, and the controls only exist once the controller adds them. Without JavaScript the sidebar is unchanged. There is no no-JS way to reorder; the stored order still applies everywhere.

### Repeated items

A group or profile that appears in more than one place in the sidebar is rendered with `--repeated`. Each occurrence is reorderable within the list it appears in, because the order belongs to that list (the parent group), not to the item.

## Rollout

One PR on the `enable-reordering` branch, built up in commits that each leave the test suite green. That keeps the PR reviewable commit by commit and easy to bisect.

### Commit 1: Add position columns and sorting helpers

1. A migration adding the four `position` columns and their indexes.
2. The sorting helpers: the SQL scope and the Ruby sort key.
3. Unit tests: positioned items come first, then alphabetical, with nil positions falling back.

### Commit 2: Use the custom order everywhere groups and profiles are listed

1. Update every read path listed in "Current state", including the tree builders.
2. Remove the association's default order.
3. Make `deep_duplicate` copy positions.
4. Tests:
   - Per-group independence: the same profile in two groups, ordered differently.
   - Tree builders and public panel queries.
   - Duplication preserving order.

No visible change yet: every list is still alphabetical until positions exist.

### Commit 3: Add the endpoint for saving an order

1. `Our::OrderingsController#update`, with validation and reset.
2. Controller tests: ownership, the 409 for exact membership, reset, and that the save is all-or-nothing.

### Commit 4: Add reorder mode to the sidebar

1. Pin SortableJS and add a `reorder` Stimulus controller.
2. Sidebar markup: the toggle, drag handles, move buttons and the live region.
3. CSS, including forced colors and large fonts.
4. System tests:
   - Dragging to reorder.
   - Keyboard move buttons, including keeping focus and the announcement.
   - The order surviving reloads and showing on the public group page and in the chat picker.
   - Forced-colors appearance.

### Commit 5 (optional, not done): Add reordering to the manage pages

Bring the same reorder controls to the manage profiles and manage groups pages, for people who prefer reordering in the main content area. Left for a follow-up: the sidebar already reaches every list, and these pages already follow the stored order.

## Open questions

- Should the public page's profile navigation (if it gains previous/next links later) follow this order? It should automatically, if it reuses the same queries.
- Should there be an account-wide "reset all orders to A–Z" in account settings? Not planned; per-list reset covers it.
