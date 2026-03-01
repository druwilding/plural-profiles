# Plan: Deep Inclusion Overrides, Profile Control, Repeated Markers & Tree Editor

## Summary

Four interconnected features to give users full control over deeply nested group trees. The core data model change is a new `inclusion_overrides` table that allows context-dependent settings at any depth in the tree — when traversing from Group A through an A→B edge, any descendant group can have its inclusion mode overridden without affecting that group's own view. On top of this: profile inclusion toggles, visual markers for repeated profiles, and a tree-based editing interface that replaces the current one-relationship-at-a-time manage_groups page.

Key decisions from discussion:
- **Context-dependent edges** (new table) over flat exclusion lists — supports per-group override of `inclusion_mode`, `included_subgroup_ids`, AND `include_direct_profiles` at any depth.
- **`include_direct_profiles`** defaults to `false` when mode is `"selected"` (auto-infer), but remains toggleable. Individual per-profile selection deferred.
- **CTE kept simple, precision in Ruby** — the recursive CTE in `descendant_group_ids` stays as a rough-but-fast membership query; precise override-aware traversal happens in `build_tree`/`walk_descendants`.
- **Tree editor complements then replaces manage_groups** — initially at a separate URL; once stable, becomes the primary interface.

---

## The Problem

The current inclusion system only operates on **immediate children** of a group relationship edge. Given a hierarchy like:

```
Alpha Clan (top)
  └── Spectrum (category)
        └── Prism Circle (sub-category)
              └── Rogue Pack (sub-group)
```

If Rogue Pack should NOT be part of Alpha Clan but IS part of Prism Circle and Spectrum, there is no way to exclude just Rogue Pack from Alpha Clan. The only options are:

- **All**: include everything (Rogue Pack leaks into Alpha Clan)
- **None**: exclude everything (loses Prism Circle too)
- **Selected**: cherry-pick immediate sub-groups of Spectrum only — can't reach two levels deep to Rogue Pack

Additionally, when adding a group with "selected" sub-groups, the group's own direct profiles are always included. Users need to be able to add only specific sub-groups without pulling in the container group's direct members.

Finally, profiles appearing in multiple places in the tree have no visual indication that they're the same person shown again, which causes confusion.

---

## Phase 1: Test Fixtures — Mirror the User's Scenario

### 1. New user

Add user `three` in `test/fixtures/users.yml` to isolate complex scenario data from existing tests that rely on user `one`'s group counts.

### 2. Groups (9 new, all under user `three`)

Add to `test/fixtures/groups.yml`:

| Fixture name   | Name         | Role in scenario                                    |
| -------------- | ------------ | --------------------------------------------------- |
| `alpha_clan`   | Alpha Clan   | A clan (top of a tree)                              |
| `delta_clan`   | Delta Clan   | Another clan                                        |
| `spectrum`     | Spectrum     | Overarching category spanning clans                 |
| `prism_circle` | Prism Circle | Sub-category inside Spectrum                        |
| `rogue_pack`   | Rogue Pack   | Sub-group of Prism Circle; its own independent clan |
| `flux`         | Flux         | Category spanning multiple clans                    |
| `echo_shard`   | Echo Shard   | Sub-group of Flux                                   |
| `static_burst` | Static Burst | Another sub-group of Flux                           |
| `delta_flux`   | Delta Flux   | Flux section specific to Delta Clan                 |

### 3. Group relationships

Add to `test/fixtures/group_groups.yml`:

| Fixture name          | Parent → Child            | inclusion_mode | Notes                                                |
| --------------------- | ------------------------- | -------------- | ---------------------------------------------------- |
| `spectrum_in_alpha`   | alpha_clan → spectrum     | `all`          | **Problem edge**: can't currently exclude rogue_pack |
| `prism_in_spectrum`   | spectrum → prism_circle   | `all`          |                                                      |
| `rogue_in_prism`      | prism_circle → rogue_pack | `all`          |                                                      |
| `flux_in_delta`       | delta_clan → flux         | `selected`     | `included_subgroup_ids: [echo_shard.id]`             |
| `echo_in_flux`        | flux → echo_shard         | `all`          |                                                      |
| `static_in_flux`      | flux → static_burst       | `all`          |                                                      |
| `delta_flux_in_delta` | delta_clan → delta_flux   | `all`          |                                                      |

### 4. Profiles (8 new, all under user `three`)

Add to `test/fixtures/profiles.yml`:

| Fixture name | Name   | Notes                                              |
| ------------ | ------ | -------------------------------------------------- |
| `stray`      | Stray  | In rogue_pack — should NOT appear in alpha_clan    |
| `ember`      | Ember  | In prism_circle — SHOULD appear in alpha_clan      |
| `drift`      | Drift  | In flux (direct) — should NOT appear in delta_clan |
| `ripple`     | Ripple | In flux (direct) — same as above                   |
| `grove`      | Grove  | In alpha_clan directly                             |
| `shadow`     | Shadow | In delta_clan directly                             |
| `mirage`     | Mirage | In echo_shard — SHOULD appear in delta_clan        |
| `spark`      | Spark  | In static_burst                                    |

### 5. Group memberships

Add to `test/fixtures/group_profiles.yml`:

| Profile → Group        | Test purpose                                    |
| ---------------------- | ----------------------------------------------- |
| `stray` → rogue_pack   | Deep exclusion: should not appear in alpha_clan |
| `stray` → prism_circle | Repeated profile: same person in two places     |
| `ember` → prism_circle | Should flow up to alpha_clan via spectrum       |
| `drift` → flux         | Direct profile exclusion test                   |
| `ripple` → flux        | Direct profile exclusion test                   |
| `grove` → alpha_clan   | Direct member of top-level clan                 |
| `shadow` → delta_clan  | Direct member of another clan                   |
| `mirage` → echo_shard  | Should appear in delta_clan via flux→echo_shard |
| `spark` → static_burst | Should NOT appear in delta_clan (not selected)  |

### Test scenarios these fixtures enable

1. **Deep exclusion**: Alpha Clan → Spectrum → Prism Circle → Rogue Pack. Want to exclude Rogue Pack from Alpha Clan without losing Prism Circle.
2. **Direct profile control**: Flux in Delta Clan with "selected" sub-groups — Drift and Ripple (direct Flux members) should not appear in Delta Clan, only Mirage (in Echo Shard) should.
3. **Repeated profiles**: Stray appears in both Rogue Pack and Prism Circle — should be marked as repeated in the tree view.
4. **Selected sub-groups**: Delta Clan includes Flux with only Echo Shard selected — Static Burst and its members should not appear.

---

## Phase 2: Data Model — `inclusion_overrides` Table + `include_direct_profiles`

### 6. Migration: `AddIncludeDirectProfilesToGroupGroups`

Add `include_direct_profiles` boolean column to `group_groups`:
- Default: `true`
- Not null
- Handles the immediate-edge profile control (e.g., Flux in Delta Clan shouldn't bring Flux's direct profiles when mode is `selected`)

### 7. Migration: `CreateInclusionOverrides`

New table `inclusion_overrides`:

| Column                    | Type     | Default | Null | Notes                              |
| ------------------------- | -------- | ------- | ---- | ---------------------------------- |
| `id`                      | bigint   | auto    | no   | PK                                 |
| `group_group_id`          | bigint   | —       | no   | FK → group_groups (cascade delete) |
| `target_group_id`         | bigint   | —       | no   | FK → groups (cascade delete)       |
| `inclusion_mode`          | string   | `"all"` | no   | `all` / `selected` / `none`        |
| `included_subgroup_ids`   | jsonb    | `[]`    | no   |                                    |
| `include_direct_profiles` | boolean  | `true`  | no   |                                    |
| `created_at`              | datetime | —       | no   |                                    |
| `updated_at`              | datetime | —       | no   |                                    |

Indexes:
- Unique on `(group_group_id, target_group_id)`
- FK constraints with `on_delete: :cascade` for both FKs

### 8. Model: `InclusionOverride`

Create `app/models/inclusion_override.rb`:
- `belongs_to :group_group`
- `belongs_to :target_group, class_name: "Group"`
- Validates `inclusion_mode` in `%w[all selected none]`
- Validates uniqueness of `target_group_id` scoped to `group_group_id`
- Validates that `target_group_id` is reachable from `group_group.child_group`

### 9. Update `GroupGroup` model

In `app/models/group_group.rb`:
- Add `has_many :inclusion_overrides, dependent: :destroy`

### 10. Update `Group` model

In `app/models/group.rb`:
- Add `has_many :inclusion_overrides, foreign_key: :target_group_id, dependent: :destroy`

---

## Phase 3: Deep Exclusion — Apply Overrides in Tree Building

### 11. Modify `Group#build_tree` (~line 163)

Accept an additional `overrides_map` parameter: `{ target_group_id → { inclusion_mode:, included_subgroup_ids:, include_direct_profiles: } }`

When processing each child group:
1. Check if `overrides_map[child_group_id]` exists
2. If so, use the override's settings instead of the edge's own `inclusion_mode` / `included_subgroup_ids`
3. Pass the same `overrides_map` through recursive calls

### 12. Modify `Group#walk_descendants` (~line 142)

Same override-aware logic for `descendant_sections`.

### 13. Modify `descendant_tree` and `descendant_sections`

In `app/models/group.rb` (~lines 101, 121):
- Preload overrides: query `InclusionOverride` for all `group_group_ids` present in `children_map`
- Build `overrides_by_edge`: `{ group_group_id → { target_group_id → override } }`
- When recursing from a specific edge, merge that edge's overrides into the `overrides_map`

### 14. Update `descendant_group_ids` CTE

**For now**: keep the CTE as a rough membership set. Create a new `visible_descendant_group_ids(edge_overrides)` method that uses Ruby tree traversal for precise override-aware results. Update `all_profiles` to use the precise set when overrides exist.

**Later optimisation**: extend the CTE to LEFT JOIN `inclusion_overrides` and carry `origin_edge_id`.

### 15. Handle `include_direct_profiles`

In `build_tree`: when `include_direct_profiles` is `false` (on the edge or override), set `profiles: []` for that node.

In `walk_descendants`: skip the group's profiles when the flag is false.

---

## Phase 4: Profile Control in UI

### 16. Update controller

In `app/controllers/our/groups_controller.rb` `update_relationship` (~line 101):
- Accept `include_direct_profiles` parameter
- When `inclusion_mode` changes to `"selected"`, default `include_direct_profiles` to `false`
- Allow explicit override back to `true` via checkbox

### 17. Update manage_groups view

In `app/views/our/groups/manage_groups.html.haml`:
- Add "Include direct profiles" checkbox to the inclusion form for each child group
- Wire to `include_direct_profiles` param

### 18. Update Stimulus controller

In `app/javascript/controllers/inclusion_controller.js`:
- Add target for `include_direct_profiles` checkbox
- When mode → `"selected"`: uncheck it; when mode → `"all"`: check it
- Leave editable for manual override in all modes

---

## Phase 5: Tree Editor

### 19. New route and action

Add `tree_editor` member route to `our/groups` in `config/routes.rb`:
```ruby
member { get :tree_editor }
```

### 20. Tree editor view

Create `app/views/our/groups/tree_editor.html.haml`:
- Two-column `.explorer`-style layout
- Left: full descendant tree with edit controls on each node
- Right: palette of available groups not yet in the tree
- Each node shows: name, avatar, inclusion mode selector, "Include profiles" toggle, remove button
- Nodes with `selected` mode show sub-group checkboxes
- Nodes with overrides show override settings

### 21. Recursive editor partial

Create `app/views/our/groups/_tree_editor_node.html.haml`:
- Similar to public `_tree_node.html.haml` but with controls
- Expand/collapse to drill into any depth
- At any depth, each sub-group shows inclusion controls
- Changes create/update `InclusionOverride` (or modify `GroupGroup` for immediate children)

### 22. Tree editor Stimulus controller

Create `app/javascript/controllers/tree_editor_controller.js`:
- Expand/collapse, mode toggles, checkbox state
- Submits changes via `fetch` to AJAX endpoints
- Updates tree in-place via Turbo Streams or DOM manipulation

### 23. AJAX endpoints

Add to `Our::GroupsController`:
- `PATCH update_override` — create/update/delete `InclusionOverride` for a target group within an edge
- `POST add_group_to_tree` — add a group at a specific position
- `DELETE remove_group_from_tree` — remove a group from the tree

### 24. Navigation

Add link to tree editor from group show page, alongside or replacing "Manage groups".

### 25. CSS

Add to `app/assets/stylesheets/application.css`:
- `.tree-editor` layout (reuse `.explorer` grid pattern)
- `.tree-editor__node-controls` for inline selectors
- `.tree-editor__palette` for available groups panel
- `@media (forced-colors: active)` rules for all interactive controls

---

## Phase 6: Repeated Profile Markers ✅ DONE

### 26. Track seen profiles in tree building

Modify `Group#descendant_tree` / `build_tree` in `app/models/group.rb`:
- Pass a `seen_profile_ids` Set through recursion
- Each profile gets `:repeated` boolean — `false` on first occurrence, `true` on subsequent

### 27. Update tree node partial

In `app/views/groups/_tree_node.html.haml`:
- Accept `seen_profiles` Set as a local
- When rendering a profile already in the set, add `.tree__label--repeated` class
- Add accessible label: `[also in other groups]` (visually hidden or as title)

### 28. Initialise in show view

In `app/views/groups/show.html.haml`:
- Create `seen_profiles = Set.new` before rendering tree nodes
- Pass through to each `_tree_node` render

### 29. CSS

Add to `app/assets/stylesheets/application.css`:
```css
.tree__label--repeated {
  opacity: 0.55;
  font-style: italic;
}

@media (forced-colors: active) {
  .tree__label--repeated {
    opacity: 1;
    color: GrayText;
  }
}
```

---

## Phase 7: Tests

### 30. `InclusionOverride` model tests

Create `test/models/inclusion_override_test.rb`:
- Uniqueness scoped to `group_group_id`
- `inclusion_mode` validation
- Target group reachability validation
- Cascade deletes when `group_group` destroyed
- Cascade deletes when target group destroyed

### 31. Expand `Group` model tests

In `test/models/group_test.rb`:
- **Deep exclusion**: set up alpha_clan → spectrum → prism_circle → rogue_pack, add override on the alpha→spectrum edge targeting prism_circle with `selected` mode excluding rogue_pack. Assert rogue_pack not in `descendant_tree` from alpha_clan but IS in tree from spectrum.
- **`all_profiles` respects overrides**: same setup, assert Stray (in rogue_pack) not in `alpha_clan.all_profiles` but IS in `spectrum.all_profiles`.
- **`include_direct_profiles: false`**: set up flux → delta_clan with `include_direct_profiles: false`. Assert Drift/Ripple not in delta_clan tree but Mirage (in echo_shard) IS.
- **Repeated profiles**: assert profiles in multiple groups get `repeated: true` on second occurrence.

### 32. Expand controller tests

In `test/controllers/our/groups_controller_test.rb`:
- `update_relationship` with `include_direct_profiles` param
- `update_override` create/update/delete
- Auth tests for all new endpoints

### 33. System tests

In `test/system/group_management_test.rb`:
- Tree editor: navigate, toggle modes, verify public view reflects changes
- Deep exclusion: exclude a group 3 levels deep, verify it disappears from public tree
- Profile exclusion: toggle `include_direct_profiles`, verify profiles appear/disappear
- Repeated markers: verify `.tree__label--repeated` on duplicated profiles

---

## Verification

```sh
bin/rails test test/models/inclusion_override_test.rb
bin/rails test test/models/group_test.rb
bin/rails test test/models/group_group_test.rb
bin/rails test test/controllers/our/groups_controller_test.rb
bin/rails test:system
bin/rubocop
```

Manual: load fixtures, visit public group page, confirm Rogue Pack excluded from Alpha Clan tree but visible in Spectrum tree; confirm Drift/Ripple excluded from Delta Clan when Flux has `include_direct_profiles: false`.

---

## Implementation Order

1. **Phase 6** (repeated markers) — ✅ DONE
2. **Phase 1** (fixtures) — enables testing from the start
3. **Phase 2** (data model) — lays foundation
4. **Phase 3** (deep exclusion logic) — the core feature
5. **Phase 4** (profile control) — small addition on top of Phase 2/3
6. **Phase 5** (tree editor) — largest UI effort, builds on all prior phases
7. **Phase 7** (tests) — written alongside each phase, listed last for organisation
