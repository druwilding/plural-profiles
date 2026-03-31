# Plan: Private sidebar tree overhaul

Replace the flat "Groups / Profiles" lists in the authenticated sidebar with a fully expandable tree that mirrors the public group tree — but showing **all** groups across the account, with labels, repeated-item styling, and orphaned profiles.

## Design decisions

| Question               | Answer                                                                                                |
| ---------------------- | ----------------------------------------------------------------------------------------------------- |
| Link behaviour         | Normal Turbo navigation links to `our/groups/:id` and `our/profiles/:id` — **not** AJAX panel-loading |
| Top-level roots        | Only parentless groups appear as tree roots (easy to change later)                                    |
| Inclusion overrides    | Ignored — the private sidebar shows everything unconditionally                                        |
| Account / Themes links | Stay at the bottom of the sidebar, below the tree                                                     |
| Labels                 | Shown as `label-badge` pills inside the tree, on both groups and profiles                             |

---

## Current state

### Private sidebar (`app/views/our/_sidebar.html.haml`)

- Flat list of all groups (alpha-sorted, shows avatars + labels).
- Flat list of all profiles (alpha-sorted, shows avatars + labels).
- Data comes from `OurSidebar` concern: `@sidebar_groups` and `@sidebar_profiles` are simple `order_by_name_and_labels` queries.
- Expand/collapse uses native `<details>` with `details-persist` Stimulus controller.
- Layout grid: `260px` sidebar column.
- "New group", "New profile" action links at top of each section.
- "Themes" and "Account" links at the bottom.

### Public tree (`app/views/groups/show.html.haml` + `_tree_node.html.haml`)

- Single root group with recursive `descendant_tree` nodes.
- Uses `tree` Stimulus controller for expand/collapse and AJAX-loaded content panels.
- Repeated profiles get `tree__label--repeated` styling (italic + 55% opacity).
- Tree CSS: `.tree`, `.tree__folder`, `.tree__leaf`, `.tree__row`, `.tree__arrow-btn`, `.tree__item`, `.tree__label`, `.tree__avatar`, etc.
- Explorer layout: `.explorer` (grid 280px sidebar + 1fr content), `.explorer__sidebar`, `.explorer__content`.

---

## Target design

```
┌─────────────────────────────────┐
│  Home                           │
│  New group · New profile        │
├─────────────────────────────────┤
│ ▶ Top-Level Group A  [label]    │
│   ├─ ▶ Sub-Group B  [label]    │
│   │   ├─ Profile X             │
│   │   └─ Profile Y  [label]    │
│   ├─ Profile Z                 │
│   └─ Profile X  (repeated)     │
│ ▶ Top-Level Group C            │
│   └─ ▶ Sub-Group B  (repeated) │
│       └─ ...                   │
├─────────────────────────────────┤
│ Profiles without groups         │
│   ├─ Orphan Profile 1          │
│   └─ Orphan Profile 2          │
├─────────────────────────────────┤
│  Themes                        │
│  Account                       │
└─────────────────────────────────┘
```

- Tree items are **Turbo navigation links** (no AJAX panels).
- **Groups** link to `our_group_path(group)`.
- **Profiles** link to `our_profile_path(profile)`.
- The active page's tree item gets a highlight (reuse the same `sidebar__item--active` / `tree__item--active` approach).
- Labels are shown inline as small `label-badge` pills.
- Repeated items (a sub-group or profile that already appeared higher in the tree) get the `tree__label--repeated` greyed-out italic style.
- Orphaned profiles (profiles not in any group) get their own collapsible section at the bottom.
- Sidebar width increases from `260px` to `300px` (or possibly `320px` — test and adjust).
- Expand/collapse state for each tree folder is persisted in `localStorage` via a lightweight Stimulus controller.

---

## Implementation steps

### 1. New model method: `User#sidebar_tree`

**File:** `app/models/user.rb` (or a new concern `SidebarTree`)

Build the full sidebar tree data structure in a single method so the controller concern stays thin.

```ruby
def sidebar_tree
  groups_by_id = groups.includes(:profiles, :parent_links,
    avatar_attachment: :blob,
    profiles: { avatar_attachment: :blob }
  ).index_by(&:id)

  # Top-level groups: those with no parent_links within this user's groups
  all_child_ids = GroupGroup.where(parent_group_id: groups.select(:id))
                            .pluck(:child_group_id).to_set
  top_level = groups_by_id.values
                           .reject { |g| all_child_ids.include?(g.id) }
                           .sort_by(&:name_and_label_sort_key)

  # Build a global children map for all of this user's groups
  children_map = GroupGroup.where(parent_group_id: groups.select(:id))
                           .pluck(:parent_group_id, :child_group_id)
                           .group_by(&:first)
                           .transform_values { |rows| rows.map(&:last) }

  seen_profile_ids = Set.new
  seen_group_ids = Set.new

  trees = top_level.map do |root|
    build_sidebar_node(root, children_map, groups_by_id, seen_profile_ids, seen_group_ids)
  end

  # Orphaned profiles: not in any group
  grouped_profile_ids = GroupProfile.where(group_id: groups.select(:id))
                                    .pluck(:profile_id).to_set
  orphans = profiles.includes(avatar_attachment: :blob)
                    .where.not(id: grouped_profile_ids)
                    .order_by_name_and_labels

  { trees: trees, orphan_profiles: orphans }
end
```

The recursive `build_sidebar_node` method returns:

```ruby
{
  group: <Group>,
  repeated: true/false,    # true if this group ID was already seen
  profiles: [
    { profile: <Profile>, repeated: true/false },
    ...
  ],
  children: [ ...child nodes... ]
}
```

Key differences from the public `descendant_tree`:
- No inclusion overrides — show everything.
- Tracks seen groups AND profiles globally across all roots (not per-root), so a group that's a child of two different top-level groups gets `repeated: true` on its second appearance.
- Profiles within a group are still expanded even when the group itself is repeated (the management sidebar needs navigability). Labels are included on both group and profile nodes.

### 2. Update `OurSidebar` concern

**File:** `app/controllers/concerns/our_sidebar.rb`

Replace the current `set_sidebar_data` method:

```ruby
def set_sidebar_data
  return unless authenticated?

  sidebar = Current.user.sidebar_tree
  @sidebar_trees = sidebar[:trees]
  @sidebar_orphan_profiles = sidebar[:orphan_profiles]
end
```

The old `@sidebar_groups` and `@sidebar_profiles` instance variables are retired.

### 3. New partial: `app/views/our/_sidebar_tree_node.html.haml`

Recursive partial for each group node in the private sidebar tree. Similar to the public `groups/_tree_node.html.haml` but:

- Uses `sidebar__` BEM-style CSS classes (or reuses `tree__` classes — see CSS section).
- Links point to `our_group_path` / `our_profile_path` (not public UUID routes).
- Shows label badges after names.
- Uses `details-persist` controller (or a new sibling) for expand/collapse persistence keyed by `"sidebar-group-#{group.id}"`.
- Marks the active item via `@group` / `@profile` instance variables from the current page.

```haml
-# Recursive sidebar tree node.
-# Locals: node (hash with :group, :profiles, :children, :repeated)
- group = node[:group]
- profiles = Array(node[:profiles])
- children = Array(node[:children])
- is_active = (@group && @group.id == group.id)
- has_children = children.any? || profiles.any?

- if has_children
  %li.sidebar-tree__folder
    %details{open: true, data: { controller: "details-persist", "details-persist-key-value": "sidebar-group-#{group.id}" }}
      %summary.sidebar-tree__row{class: ("sidebar-tree__row--active" if is_active)}
        - if group.avatar.attached?
          = image_tag group.avatar.variant(resize_to_fill: [24, 24]), class: "sidebar-tree__avatar", width: 24, height: 24, alt: "", loading: "lazy"
        = link_to our_group_path(group), class: "sidebar-tree__link" do
          - if node[:repeated]
            %span.sidebar-tree__label.sidebar-tree__label--repeated= group.name
          - else
            %span.sidebar-tree__label= group.name
        - group.labels.each do |label|
          %span.label-badge.label-badge--sidebar= label
      %ul.sidebar-tree__children
        - children.each do |child_node|
          = render "our/sidebar_tree_node", node: child_node
        - profiles.each do |entry|
          - profile = entry[:profile]
          %li.sidebar-tree__leaf{class: ("sidebar-tree__leaf--active" if @profile && @profile.id == profile.id)}
            - if profile.avatar.attached?
              = image_tag profile.avatar.variant(resize_to_fill: [24, 24]), class: "sidebar-tree__avatar", width: 24, height: 24, alt: "", loading: "lazy"
            - else
              %span.sidebar-tree__avatar.sidebar-tree__avatar--placeholder
                = render "shared/plural_pride_logo"
            = link_to our_profile_path(profile), class: "sidebar-tree__link" do
              - if entry[:repeated]
                %span.sidebar-tree__label.sidebar-tree__label--repeated= profile.name
              - else
                %span.sidebar-tree__label= profile.name
            - profile.labels.each do |label|
              %span.label-badge.label-badge--sidebar= label
- else
  -# Group with no children and no profiles — render as a simple leaf
  %li.sidebar-tree__leaf{class: ("sidebar-tree__leaf--active" if is_active)}
    - if group.avatar.attached?
      = image_tag group.avatar.variant(resize_to_fill: [24, 24]), class: "sidebar-tree__avatar", width: 24, height: 24, alt: "", loading: "lazy"
    = link_to our_group_path(group), class: "sidebar-tree__link" do
      - if node[:repeated]
        %span.sidebar-tree__label.sidebar-tree__label--repeated= group.name
      - else
        %span.sidebar-tree__label= group.name
    - group.labels.each do |label|
      %span.label-badge.label-badge--sidebar= label
```

### 4. Rewrite `app/views/our/_sidebar.html.haml`

Replace the flat structure with the tree layout:

```
┌──────────────────────────────┐
│ Home  ·  New group  ·  New profile │   ← action links
├──────────────────────────────┤
│ <details "Groups">           │   ← collapsible section header
│   <ul>                       │
│     <sidebar_tree_node> ×N   │   ← recursive for each top-level group
│   </ul>                      │
│ </details>                   │
├──────────────────────────────┤
│ <details "Ungrouped profiles"> │  ← only if orphans exist
│   <ul>                       │
│     <leaf> ×N                │
│   </ul>                      │
│ </details>                   │
├──────────────────────────────┤
│ Themes                       │
│ Account                      │
└──────────────────────────────┘
```

The top-level `<details>` for "Groups" and "Ungrouped profiles" each use `details-persist` for remembering open/closed state.

### 5. CSS changes

**File:** `app/assets/stylesheets/application.css`

#### a) Widen the sidebar

Change `.layout` grid from `260px` to `300px`:

```css
.layout {
  grid-template-columns: 300px 1fr;
}
```

(Test at 300px — increase to 320px if labels cause overflow.)

#### b) Add `sidebar-tree__` classes

Create new CSS rules for the private sidebar tree. These will mirror the public `.tree__` styles but adapt them for the sidebar context:

- `.sidebar-tree__folder`, `.sidebar-tree__leaf`, `.sidebar-tree__row` — layout.
- `.sidebar-tree__children` — indented nested list with subtle tree guide lines (reuse `--tree-guide` colour variable).
- `.sidebar-tree__link` — inherits from `.sidebar__link` styling.
- `.sidebar-tree__avatar`, `.sidebar-tree__avatar--placeholder` — same 24×24 sizing.
- `.sidebar-tree__label--repeated` — reuse the same opacity + italic treatment from `.tree__label--repeated`.
- `.sidebar-tree__row--active`, `.sidebar-tree__leaf--active` — active-page highlight.
- Use `<details>` + `<summary>` (native HTML) for expand/collapse inside the tree, replacing the Stimulus `tree` controller's manual toggling. This is simpler for the private sidebar since we don't need AJAX panel loading.
- The `<summary>` arrow styling can reuse the existing `.sidebar summary::before` rotate pattern.

#### c) Label badge sizing in tree

The existing `.label-badge--sidebar` may need font-size and padding adjustments for the narrower tree indentation. Consider a smaller variant or ensure the badges wrap gracefully.

#### d) Forced-colours / accessibility

Add a `@media (forced-colors: active)` block for:
- `.sidebar-tree__label--repeated` → `color: GrayText`
- Tree guide lines → `border-color: CanvasText`
- Active-state highlights → `background: Highlight; color: HighlightText`

#### e) Mobile responsive

The existing mobile breakpoint collapses `.layout` to single-column and un-stickies the sidebar. No change needed for that — but test that the deeper tree nesting doesn't cause horizontal overflow on small screens. Consider adding `overflow-x: auto` on `.sidebar` at mobile widths.

### 6. Active-item highlighting

The current sidebar uses `@group` and `@profile` instance variables to detect the active page. These are already set by the individual `Our::GroupsController` and `Our::ProfilesController` actions. Keep this approach — the recursive partial checks `@group.id == group.id` or `@profile.id == profile.id` to apply the active class.

For the Home, Themes, and Account links, keep using `current_page?` helper as today.

### 7. Performance considerations

- **Eager loading:** The `sidebar_tree` method must eager-load `profiles`, `avatar_attachment: :blob`, and `profiles: { avatar_attachment: :blob }` to avoid N+1 queries. All groups for the user are loaded in a single query.
- **Children map:** A single `GroupGroup` query builds the parent→children map for the entire account.
- **Caching:** For accounts with very large trees, consider fragment caching the sidebar keyed on `[user.id, user.updated_at, groups.maximum(:updated_at), profiles.maximum(:updated_at)]`. This is optional for the first iteration.
- **Orphan query:** One query to get all `GroupProfile` profile IDs, then filter.

### 8. Tests

#### System tests

- **Tree structure:** Sign in, verify top-level groups appear as expandable tree roots.
- **Nested content:** Expand a group, verify sub-groups and profiles appear indented.
- **Repeated items:** A profile or group appearing in two places gets the repeated/dimmed style on the second occurrence.
- **Orphaned profiles:** A profile not assigned to any group appears in the "Ungrouped profiles" section.
- **Active highlighting:** Navigate to a group page, verify its tree entry is highlighted.
- **Expand/collapse persistence:** Toggle a folder closed, navigate away and back, verify it stays closed.

#### Controller tests

- Verify `@sidebar_trees` and `@sidebar_orphan_profiles` are set on authenticated requests.

#### Model tests

- `User#sidebar_tree` returns correct structure for:
  - User with no groups (empty trees, all profiles orphaned).
  - User with a simple group containing profiles.
  - User with nested groups (parent → child → grandchild).
  - User with diamond-shaped nesting (child has two parents) — child marked repeated on second appearance.
  - Profile in multiple groups — marked repeated after first appearance.

### 9. Migration path / backwards compatibility

- The old `@sidebar_groups` and `@sidebar_profiles` variables are removed. Any reference to them in views is replaced.
- No database migrations needed.
- No route changes needed.
- The public tree is completely untouched.

---

## Files to create or modify

| File                                                            | Action                                                           |
| --------------------------------------------------------------- | ---------------------------------------------------------------- |
| `app/models/user.rb` (or `app/models/concerns/sidebar_tree.rb`) | Add `sidebar_tree` + `build_sidebar_node` methods                |
| `app/controllers/concerns/our_sidebar.rb`                       | Replace `set_sidebar_data` to call `sidebar_tree`                |
| `app/views/our/_sidebar.html.haml`                              | Full rewrite to tree layout                                      |
| `app/views/our/_sidebar_tree_node.html.haml`                    | **New** — recursive tree node partial                            |
| `app/assets/stylesheets/application.css`                        | Widen sidebar, add `.sidebar-tree__*` classes, adjust responsive |
| `test/models/user_test.rb`                                      | Add `sidebar_tree` tests                                         |
| `test/system/*`                                                 | Update any system tests that reference the old sidebar structure |

---

## Open questions / follow-up

1. **Width tuning** — 300px may or may not be enough with labels + deep nesting. Needs visual testing.
2. **Very deep trees** — If someone nests 6+ levels deep, the indentation could eat all available space. Consider capping visual indent at ~4 levels or using a smaller indent step (e.g. 0.75rem instead of 1rem).
3. **Empty state** — What should the sidebar show for a brand-new user with no groups and no profiles? Currently it shows the empty sections. A brief "Create your first group or profile" prompt might be nicer.
4. **Expand/collapse default** — Should tree folders default to open or closed? Suggestion: open by default (matches current `<details open>`), with localStorage persistence overriding on subsequent visits.
5. **Search or filter** — Not in scope for this overhaul, but a future enhancement could add a filter input at the top of the sidebar for users with many items.
