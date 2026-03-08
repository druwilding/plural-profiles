# Plan: Simplified Group Management — Checkbox Tree with Cascading Hide

## Summary

Replace the current manage-groups tree editor (expand-to-configure, radio-button modes, deep override forms) with a **simple nested tree** of groups and profiles — matching the layout of the public sidebar — where each item has a **checkbox to hide/show it**. Hiding a group automatically hides all its descendants. Visibility is context-dependent: hiding Rogue Pack when managing Alpha Clan has no effect on Spectrum's own public view.

The data model shifts from a dual-layer system (modes on `group_groups` + `inclusion_overrides` for deeper descendants) to a **single `inclusion_overrides` table** storing per-item hidden state scoped to a **full traversal path** within a root group's tree. `group_groups` becomes a simple join table with no inclusion-mode columns.

JavaScript progressively enhances the form: without JS, each checkbox is inside a one-field form that submits normally. With JS, a Stimulus controller intercepts checkbox changes and sends AJAX requests, showing a brief "Saved" indicator.

### Key decisions from discussion

- **Keep add/remove on the same page** — tree with hide checkboxes at top, "Add a group" section below
- **Everything hideable** — including profiles directly on the root group
- **Implicit modes** — checkbox + cascading covers all/selected/none semantics without explicit mode columns
- **Context-dependent** — overrides are scoped to the root group being managed
- **Path-scoped** — overrides store the full traversal path (an array of group IDs from root to the target's container), so the same item can be hidden along one path but visible along another — even when the same `group_group` edge is involved

### Why path-scoped overrides?

A group can appear at multiple points in a tree, sometimes reachable through the **exact same `group_group` edge** but via different ancestor paths. Because `group_groups` has a unique constraint on `(parent_group_id, child_group_id)`, the edge `prism_circle → rogue_pack` is always ONE record regardless of how you arrived at Prism Circle.

To demonstrate, extend the existing fixtures so that Prism Circle is a child of both Spectrum and Echo Shard:

```
Alpha Clan (root)
  ├── Spectrum
  │     └── Prism Circle  (edge: prism_in_spectrum)
  │           └── Rogue Pack  (edge: rogue_in_prism)
  │                 └── Stray
  └── Echo Shard           (edge: echo_in_alpha) [NEW]
        └── Prism Circle   (edge: prism_in_echo) [NEW]
              └── Rogue Pack  (edge: rogue_in_prism) ← SAME edge record!
                    └── Stray
```

With **`(root, parent_group, target)`** — hiding Stray under Rogue Pack hides it everywhere, because `parent_group: rogue_pack` is the same for both appearances. ❌

With **`(root, group_group_id, target)`** — hiding Stray via the `rogue_in_prism` edge STILL hides it everywhere, because there's only one `rogue_in_prism` record. ❌

With **`(root, path, target)`** — we can distinguish:
- Path to Rogue Pack via Spectrum: `[spectrum, prism_circle, rogue_pack]`
- Path to Rogue Pack via Echo Shard: `[echo_shard, prism_circle, rogue_pack]`

These are different paths. Create an override for the Spectrum path → Stray is hidden only under Spectrum's branch. ✓

The `path` is an array of group IDs representing the traversal from root (exclusive) to the group containing the target (inclusive). Empty array `[]` means the target is directly on the root group.

---

## The Problem with the Current UI

1. **Too many clicks and concepts**: users must expand a `<details>`, choose a radio mode (All/Selected/None), individually check sub-groups or profiles, then hit Save. Deeper descendants need separate "Set override" / "Save override" actions.
2. **Can't fully collapse**: the tree uses `<details>` elements that must be open to configure, but there's no "collapse all" or fully-closed default state.
3. **Dual-layer data**: visibility is determined by checking `group_groups` mode columns for direct children AND `inclusion_overrides` for deeper descendants. This makes the model code complex (~250 lines of traversal logic) and hard to reason about.
4. **Mental model mismatch**: users think "I want to hide this thing" but the UI asks them to think in terms of modes and explicit selection lists.

---

## Phase 1: Migration - ✅ DONE

### 1a. Rework `inclusion_overrides` table

Create migration `ReworkInclusionOverridesForCheckboxModel`:

**Drop old columns** from `inclusion_overrides`:
- `group_group_id`
- `target_group_id`
- `subgroup_inclusion_mode`
- `included_subgroup_ids`
- `profile_inclusion_mode`
- `included_profile_ids`

**Add new columns**:
- `group_id` (bigint, not null, FK → groups, cascade delete) — the root group this override applies to
- `path` (jsonb, not null, default: `[]`) — ordered array of group IDs from root (exclusive) to the group containing the target (inclusive). Empty array for items directly on the root.
- `target_type` (string, not null) — `"Group"` or `"Profile"`
- `target_id` (bigint, not null) — ID of the hidden group or profile

**Indexes**:
- Unique on `(group_id, path, target_type, target_id)` — each item can only be hidden once per path per root. PostgreSQL's btree operator for jsonb compares structurally, so `[1,2,3]` and `[1,2,3]` are equal but `[1,3,2]` is different.
- Index on `group_id` for fast lookup when loading all overrides for a root group

**How `path` maps to the tree**:

```
Alpha Clan (root, group_id in overrides)
  ├── Spectrum
  │     └── Prism Circle
  │           └── Rogue Pack         (path to Rogue Pack: [spectrum, prism_circle, rogue_pack])
  │                 └── Stray        (profile in Rogue Pack)
  └── Echo Shard
        └── Prism Circle
              └── Rogue Pack         (path to Rogue Pack: [echo_shard, prism_circle, rogue_pack])
                    └── Stray        (same profile, different path)
```

- Hide Stray in Rogue Pack via Spectrum only:
  `(group_id: alpha_clan, path: [spectrum, prism_circle, rogue_pack], target_type: "Profile", target_id: stray)`
- Keep Stray visible via Echo Shard: no override for path `[echo_shard, prism_circle, rogue_pack]`
- Hide Spectrum from root: `(group_id: alpha_clan, path: [], target_type: "Group", target_id: spectrum)`
- Hide a root-level profile: `(group_id: alpha_clan, path: [], target_type: "Profile", target_id: grove)`

**Data migration**: translate existing overrides + edge modes into the new per-item hidden records. For each root group:
1. Walk the old `editor_tree` structure, tracking the path of group IDs at each level
2. Any group node with `hidden_from_public: true` → create override with `group_id: root.id, path: [group IDs from root to this node's parent], target_type: "Group", target_id: node.group.id`
3. Any profiles hidden by `profile_inclusion_mode: "none"` or `profile_inclusion_mode: "selected"` → create profile overrides with `path` set to the traversal path to the group the profile belongs to

### 1b. Remove mode columns from `group_groups`

Create migration `RemoveInclusionModesFromGroupGroups`:

**Drop columns**:
- `subgroup_inclusion_mode`
- `included_subgroup_ids`
- `profile_inclusion_mode`
- `included_profile_ids`

`group_groups` becomes the simple join table it was originally: just `parent_group_id`, `child_group_id`, and timestamps.

---

## Phase 2: Model Changes

### 2a. `InclusionOverride` model

Rewrite to match new schema:

```ruby
class InclusionOverride < ApplicationRecord
  belongs_to :group  # the root group

  validates :target_type, inclusion: { in: %w[Group Profile] }
  validates :target_id, uniqueness: { scope: %i[group_id path target_type] }
  validates :path, presence: true  # [] is present; nil is not
  validate :same_user
  validate :path_groups_exist

  # Convenience: normalise path to an array of integers
  before_validation :normalise_path

  private

  def normalise_path
    self.path = Array(path).map(&:to_i)
  end

  def same_user
    return unless group
    target_record = target_type.constantize.find_by(id: target_id)
    return unless target_record
    target_user_id = target_record.respond_to?(:user_id) ? target_record.user_id : nil
    errors.add(:target, "must belong to the same user") if target_user_id && target_user_id != group.user_id
  end

  def path_groups_exist
    return unless group && path.present?
    # All group IDs in the path must be reachable from the root
    reachable = group.reachable_group_ids
    path.each do |gid|
      unless reachable.include?(gid)
        errors.add(:path, "contains a group not in this tree")
        break
      end
    end
  end
end
```

### 2b. `GroupGroup` model

Strip mode-related code:
- Remove `INCLUSION_MODES` constant
- Remove `subgroup_inclusion_mode` / `profile_inclusion_mode` validations
- Remove mode-checking instance methods (`subgroup_all?`, `subgroup_selected?`, etc.)
- Remove `has_many :inclusion_overrides` (no longer linked to edges)
- Remove mode-related scopes
- Keep: `belongs_to :parent_group / :child_group`, `same_user`, `not_self_referencing`, `no_circular_reference` validations

### 2c. `Group` model — simplified tree building

**`descendant_group_ids`** — simplify CTE:
Remove mode checks. Just follow all `group_groups` edges recursively. The CTE becomes:
```sql
WITH RECURSIVE tree AS (
  SELECT :root_id AS id
  UNION
  SELECT gg.child_group_id AS id
  FROM group_groups gg
  INNER JOIN tree t ON t.id = gg.parent_group_id
)
SELECT DISTINCT id FROM tree
```
This is identical to the current `reachable_group_ids`. We can merge the two methods.

**`overrides_index`** (replaces `hidden_sets`):
Load all `InclusionOverride` records for this root group and return a lookup structure indexed by `(path, target_type, target_id)` — a Set of tuples. During traversal, each node knows the path taken to reach it, which is used to look up applicable overrides.

```ruby
# Returns a Set of [path, target_type, target_id] tuples
# for quick lookups during tree traversal.
# path is an array of group IDs (may be empty for root-level items).
def overrides_index
  InclusionOverride.where(group_id: id)
    .pluck(:path, :target_type, :target_id)
    .map { |path, type, tid| [Array(path).map(&:to_i), type, tid] }
    .to_set
end
```

Check during traversal: `overrides.include?([current_path, "Group", child_id])`
Check for root-level items: `overrides.include?([[], "Profile", profile_id])`

**`descendant_tree(seen_profile_ids:)`** — simplify:
1. Build `children_map` (parent → [child_ids], no mode data)
2. Load `overrides_index` for this root
3. Recursive `build_tree` that accumulates the traversal path and checks overrides at each node
4. No more modes, no more overrides_map, no more effective_settings

```ruby
def descendant_tree(seen_profile_ids: nil)
  all_ids = descendant_group_ids - [id]
  return [] if all_ids.empty?

  overrides = overrides_index
  children_map = build_children_map([id] + all_ids)
  groups_by_id = Group.where(id: all_ids)
                      .includes(profiles: { avatar_attachment: :blob }, avatar_attachment: :blob)
                      .index_by(&:id)

  seen_profile_ids ||= Set.new
  build_tree(id, [], children_map, groups_by_id, seen_profile_ids, overrides)
end
```

The `build_tree` recursive method accumulates a `path` (array of group IDs). At each parent node with path `current_path`:
- For each child group: compute `child_path = current_path + [child.id]`. Check `overrides.include?([current_path, "Group", child.id])` — if hidden, skip entirely (no recursion).
- For profiles in the child group: check `overrides.include?([child_path, "Profile", profile.id])` — the path includes the group containing the profile.

```ruby
def build_tree(parent_id, current_path, children_map, groups_by_id, seen_profile_ids, overrides)
  (children_map[parent_id] || [])
    .filter_map { |entry| groups_by_id[entry[:id]] ? [groups_by_id[entry[:id]], entry] : nil }
    .reject { |g, _| overrides.include?([current_path, "Group", g.id]) }
    .sort_by { |g, _| g.name }
    .map do |g, entry|
      child_path = current_path + [g.id]
      visible_profiles = g.profiles.reject { |p| overrides.include?([child_path, "Profile", p.id]) }

      {
        group: g,
        profiles: tag_profiles(visible_profiles, seen_profile_ids),
        children: build_tree(g.id, child_path, children_map, groups_by_id, seen_profile_ids, overrides)
      }
    end
end
```

**`descendant_sections`** — same approach: traverse depth-first, accumulate path, check overrides.

**`all_profiles`** — must now traverse the tree rather than using flat set subtraction, since a profile might be hidden along one path but visible along another:
1. Walk the tree depth-first, accumulating path, collecting visible profiles
2. At each group, check which child groups are hidden (skip them) and which profiles are hidden (exclude them)
3. Return de-duplicated profiles

**`management_tree`** (replaces `editor_tree`):
Full unfiltered tree including hidden items, with hidden/cascade-hidden flags:
```ruby
# Returns an array of nodes:
# { group:, profiles:, children:, hidden:, cascade_hidden:, path: }
# hidden: true if this specific item has an override at this path
# cascade_hidden: true if a parent group in the path is hidden
# path: array of group IDs from root to this node's parent (needed for toggle forms)
```
Profiles within each node also carry `hidden`, `cascade_hidden`, and `container_path` (path including their containing group) fields.

**Remove** (no longer needed):
- `build_overrides_by_edge`, `effective_settings`, `merge_overrides`
- `build_selected_children`, `walk_selected_descendants`
- `collect_profile_visibility`, `collect_selected_profile_visibility`
- `collect_traversed_group_ids`, `collect_traversed_ids`, `collect_selected_traversed_ids`
- `filter_profiles_by_mode`
- `build_editor_nodes`, `node_hidden_from_public?`
- `hidden_sets` (replaced by `overrides_index`)

This should reduce the Group model from ~564 lines to roughly ~250.

---

## Phase 3: Routes & Controller

### 3a. Routes

**Remove** member routes:
- `patch :update_relationship`
- `patch :update_override`
- `delete :remove_override`

**Add** member route:
- `patch :toggle_visibility`

Updated routes block:
```ruby
resources :our_groups, path: "our/groups", controller: "our/groups" do
  member do
    get :manage_profiles
    post :add_profile
    delete :remove_profile
    post :add_group
    delete :remove_group
    patch :regenerate_uuid
    get :manage_groups
    patch :toggle_visibility
  end
end
```

### 3b. Controller — `toggle_visibility` action

```ruby
def toggle_visibility
  target_type = params[:target_type].to_s
  target_id = params[:target_id].to_i
  path = JSON.parse(params[:path] || "[]").map(&:to_i)

  unless %w[Group Profile].include?(target_type)
    return respond_to do |format|
      format.html { redirect_to manage_groups_our_group_path(@group), alert: "Invalid target." }
      format.json { render json: { error: "Invalid target" }, status: :unprocessable_entity }
    end
  end

  # Verify target belongs to current user
  target = target_type.constantize.find_by(id: target_id, user_id: Current.user.id)
  unless target
    return respond_to do |format|
      format.html { redirect_to manage_groups_our_group_path(@group), alert: "Not found." }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  # Verify all groups in path belong to current user and are in this tree
  if path.any?
    reachable = @group.reachable_group_ids
    unless path.all? { |gid| reachable.include?(gid) }
      return respond_to do |format|
        format.html { redirect_to manage_groups_our_group_path(@group), alert: "Not found." }
        format.json { render json: { error: "Not found" }, status: :not_found }
      end
    end
  end

  hidden = params[:hidden] == "1" || params[:hidden] == "true"
  override = InclusionOverride.find_by(
    group_id: @group.id, path: path,
    target_type: target_type, target_id: target_id
  )

  if hidden && !override
    InclusionOverride.create!(
      group_id: @group.id, path: path,
      target_type: target_type, target_id: target_id
    )
  elsif !hidden && override
    override.destroy!
  end

  respond_to do |format|
    format.html { redirect_to manage_groups_our_group_path(@group), notice: "Visibility updated." }
    format.json { render json: { hidden: hidden }, status: :ok }
  end
end
```

**Remove** actions: `update_relationship`, `update_override`, `remove_override`.

**Update** `before_action :set_group` — remove the deleted actions.

**Update** `manage_groups` action:
```ruby
def manage_groups
  @management_tree = @group.management_tree
  excluded_ids = @group.ancestor_group_ids | @group.child_group_ids | [@group.id]
  @available_groups = Current.user.groups
    .where.not(id: excluded_ids)
    .includes(avatar_attachment: :blob)
    .order(:name)
end
```

---

## Phase 4: Views

### 4a. `manage_groups.html.haml`

Replace the current page with:

```haml
- content_for(:title) { "Manage groups in #{@group.name} — Plural Profiles" }

%h1
  Manage groups in
  = @group.name

- if @management_tree.any?
  .tree-editor
    %p.tree-editor__hint
      Uncheck a group or profile to hide it from the public view of
      = succeed "." do
        %strong= link_to @group.name, group_path(@group.uuid), target: "_blank", rel: "noopener noreferrer"
      Hiding a group also hides everything inside it.
    %ul.tree-editor__tree{"aria-label": "Group tree for #{@group.name}", "data-controller": "visibility-toggle"}
      = render partial: "our/groups/manage_groups_node", collection: @management_tree, as: :node, locals: { root_group: @group }
- else
  .card
    %p This group has no sub-groups yet. Add one below.

-# root group's own direct profiles
- if @root_profiles.any?
  %h2 Profiles directly in #{@group.name}
  %ul.tree-editor__tree{"data-controller": "visibility-toggle"}
    - @root_profiles.each do |entry|
      = render "our/groups/manage_groups_profile_node", entry: entry, root_group: @group

%h2
  Add a group to
  = @group.name
-# ... existing add-group UI stays the same ...
```

### 4b. `_manage_groups_node.html.haml` — replacement (recursive)

Simpler structure: a tree node with a checkbox, name, "hidden" tag, and nested children (groups + profiles).

```haml
-# Recursive tree node for the management tree.
-# Locals: node (hash from Group#management_tree), root_group
- group = node[:group]
- path = node[:path]
- container_path = node[:container_path]
- hidden = node[:hidden]
- cascade_hidden = node[:cascade_hidden]
- effectively_hidden = hidden || cascade_hidden
- children = node[:children]
- profiles = node[:profiles]
- has_children = children.any? || profiles.any?

%li.tree-editor__node{class: ("tree-editor__node--hidden" if effectively_hidden)}
  .tree-editor__row
    .tree-editor__check
      -# No-JS form: each checkbox is a standalone form
      = form_with url: toggle_visibility_our_group_path(root_group), method: :patch,
        class: "tree-editor__toggle-form", data: { visibility_toggle_target: "form" } do
        = hidden_field_tag :path, path.to_json
        = hidden_field_tag :target_type, "Group"
        = hidden_field_tag :target_id, group.id
        = hidden_field_tag :hidden, hidden ? "0" : "1"
        %label.tree-editor__checkbox-label
          = check_box_tag :visible, "1", !hidden,
            disabled: cascade_hidden,
            data: { action: "change->visibility-toggle#toggle",
                    path: path.to_json,
                    target_type: "Group", target_id: group.id,
                    visibility_toggle_target: "checkbox" }
          .tree-editor__item-info
            - if group.avatar.attached?
              = image_tag group.avatar.variant(resize_to_fill: [24, 24]),
                class: "tree__avatar", width: 24, height: 24, alt: ""
            - else
              %span.tree__avatar.tree__avatar--placeholder{"aria-hidden": "true"}
                = render "shared/plural_pride_logo"
            %span.tree-editor__name= group.name
        - if effectively_hidden
          %span.tree-editor__tag.tree-editor__tag--hidden hidden
        %noscript
          = submit_tag hidden ? "Show" : "Hide", class: "btn btn--small"
    .tree-editor__save-indicator{data: { visibility_toggle_target: "indicator" }}

  - if has_children
    %ul.tree-editor__children
      - children.each do |child_node|
        = render "our/groups/manage_groups_node", node: child_node, root_group: root_group
      - profiles.each do |entry|
        = render "our/groups/manage_groups_profile_node", entry: entry, root_group: root_group
```

**Path semantics in nodes**:
- `path`: the path from root to this node's parent (used when hiding/showing this group as a child of that parent). For direct children of root, this is `[]`.
- `container_path`: the path from root to this group itself, i.e. `path + [group.id]`. Used by profile overrides within this group.

### 4c. `_manage_groups_profile_node.html.haml` — new partial

```haml
-# Profile leaf node for the management tree.
-# Locals: entry (hash with :profile, :hidden, :cascade_hidden, :container_path), root_group
- profile = entry[:profile]
- container_path = entry[:container_path]
- hidden = entry[:hidden]
- cascade_hidden = entry[:cascade_hidden]
- effectively_hidden = hidden || cascade_hidden

%li.tree-editor__node.tree-editor__node--profile{class: ("tree-editor__node--hidden" if effectively_hidden)}
  .tree-editor__row
    .tree-editor__check
      = form_with url: toggle_visibility_our_group_path(root_group), method: :patch,
        class: "tree-editor__toggle-form", data: { visibility_toggle_target: "form" } do
        = hidden_field_tag :path, container_path.to_json
        = hidden_field_tag :target_type, "Profile"
        = hidden_field_tag :target_id, profile.id
        = hidden_field_tag :hidden, hidden ? "0" : "1"
        %label.tree-editor__checkbox-label
          = check_box_tag :visible, "1", !hidden,
            disabled: cascade_hidden,
            data: { action: "change->visibility-toggle#toggle",
                    path: container_path.to_json,
                    target_type: "Profile", target_id: profile.id,
                    visibility_toggle_target: "checkbox" }
          .tree-editor__item-info
            - if profile.avatar.attached?
              = image_tag profile.avatar.variant(resize_to_fill: [24, 24]),
                class: "tree__avatar", width: 24, height: 24, alt: ""
            - else
              %span.tree__avatar.tree__avatar--placeholder{"aria-hidden": "true"}
                = render "shared/plural_pride_logo"
            %span.tree-editor__name= profile.name
        - if effectively_hidden
          %span.tree-editor__tag.tree-editor__tag--hidden hidden
        %noscript
          = submit_tag hidden ? "Show" : "Hide", class: "btn btn--small"
    .tree-editor__save-indicator{data: { visibility_toggle_target: "indicator" }}
```

---

## Phase 5: JavaScript — `visibility_toggle_controller.js`

Replaces `inclusion_controller.js`. Provides AJAX saves with feedback.

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "form", "indicator"]

  async toggle(event) {
    const checkbox = event.target
    const hidden = !checkbox.checked
    const targetType = checkbox.dataset.targetType
    const targetId = checkbox.dataset.targetId

    // Find the closest form for this checkbox
    const form = checkbox.closest(".tree-editor__toggle-form")
    if (!form) return

    // Update the hidden field value
    const hiddenField = form.querySelector('input[name="hidden"]')
    if (hiddenField) hiddenField.value = hidden ? "1" : "0"

    // Find the save indicator for this row
    const row = checkbox.closest(".tree-editor__node")
    const indicator = row?.querySelector(".tree-editor__save-indicator")

    try {
      const response = await fetch(form.action, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
          "Accept": "application/json"
        },
        body: new URLSearchParams(new FormData(form))
      })

      if (response.ok) {
        // Show saved indicator
        if (indicator) {
          indicator.textContent = "Saved"
          indicator.classList.add("tree-editor__save-indicator--visible")
          setTimeout(() => {
            indicator.classList.remove("tree-editor__save-indicator--visible")
          }, 1500)
        }

        // Cascade: if hiding a group, disable and dim descendant checkboxes
        if (targetType === "Group") {
          this.cascadeGroupVisibility(row, hidden)
        }
      } else {
        // Revert on failure
        checkbox.checked = !hidden
        if (indicator) {
          indicator.textContent = "Error"
          indicator.classList.add("tree-editor__save-indicator--error")
          setTimeout(() => {
            indicator.classList.remove("tree-editor__save-indicator--error")
          }, 2000)
        }
      }
    } catch {
      checkbox.checked = !hidden
    }
  }

  cascadeGroupVisibility(groupNode, hidden) {
    const childList = groupNode.querySelector(".tree-editor__children")
    if (!childList) return

    const descendantNodes = childList.querySelectorAll(".tree-editor__node")
    descendantNodes.forEach(node => {
      const cb = node.querySelector(':scope > .tree-editor__row input[type="checkbox"]')
      const tag = node.querySelector(":scope > .tree-editor__row .tree-editor__tag--hidden")

      if (hidden) {
        node.classList.add("tree-editor__node--hidden")
        if (cb) cb.disabled = true
        if (!tag) {
          // Add hidden tag
          const newTag = document.createElement("span")
          newTag.className = "tree-editor__tag tree-editor__tag--hidden"
          newTag.textContent = "hidden"
          const label = node.querySelector(":scope > .tree-editor__row .tree-editor__checkbox-label")
          if (label) label.appendChild(newTag)
        }
      } else {
        // Only un-cascade nodes that aren't directly hidden themselves
        const nodeCheckbox = node.querySelector(':scope > .tree-editor__row input[type="checkbox"]')
        if (nodeCheckbox?.checked) {
          node.classList.remove("tree-editor__node--hidden")
          if (cb) cb.disabled = false
          if (tag) tag.remove()
        } else {
          // Node is directly hidden — keep it hidden but re-enable its checkbox
          if (cb) cb.disabled = false
        }
      }
    })
  }
}
```

---

## Phase 6: CSS Updates

Update the `.tree-editor` styles in `application.css`:

**Remove** styles for:
- `.tree-editor__details`, `.tree-editor__summary`, `.tree-editor__summary-row`, etc.
- `.tree-editor__form`, `.tree-editor__fieldsets`, `.tree-editor__fieldset`
- `.tree-editor__radio-group`, `.tree-editor__checkbox-list`
- `.tree-editor__override-note`, `.tree-editor__actions`
- `.tree-editor__tag--override`

**Add/update** styles for:
- `.tree-editor__row` — flex row with checkbox + name + tag + indicator
- `.tree-editor__check` — container for checkbox form
- `.tree-editor__toggle-form` — inline form (display: contents when JS active)
- `.tree-editor__checkbox-label` — flex container for checkbox + avatar + name
- `.tree-editor__item-info` — avatar + name group
- `.tree-editor__save-indicator` — fade-in/out "Saved" text
- `.tree-editor__node--hidden` — dimmed appearance (opacity, muted text)
- `.tree-editor__node--profile` — leaf node styling

Key CSS additions:
```css
.tree-editor__save-indicator {
  font-size: 0.8rem;
  color: var(--success);
  opacity: 0;
  transition: opacity 0.2s;
}
.tree-editor__save-indicator--visible {
  opacity: 1;
}
.tree-editor__save-indicator--error {
  color: var(--error);
  opacity: 1;
}
.tree-editor__node--hidden {
  opacity: 0.5;
}
.tree-editor__node--hidden .tree-editor__children {
  opacity: 0.7;  /* compound dimming for cascaded items */
}

@media (forced-colors: active) {
  .tree-editor__node--hidden {
    opacity: 1;
    color: GrayText;
  }
  .tree-editor__save-indicator {
    color: CanvasText;
  }
  .tree-editor__save-indicator--error {
    color: CanvasText;
  }
}
```

---

## Phase 7: Test Fixture Updates

### 7a. Remove mode data from `group_groups` fixtures

Strip `subgroup_inclusion_mode`, `included_subgroup_ids`, `profile_inclusion_mode`, `included_profile_ids` from all fixtures in `test/fixtures/group_groups.yml`. Each becomes just `parent_group → child_group`.

### 7b. Rewrite `inclusion_overrides` fixtures

The current `test/fixtures/inclusion_overrides.yml` fixture references the old schema. Rewrite with the new schema using `path` (array of group IDs) to identify tree positions:

```yaml
rogue_pack_hidden_in_alpha_via_spectrum:
  group: alpha_clan
  path: <%= [ActiveRecord::FixtureSet.identify(:spectrum), ActiveRecord::FixtureSet.identify(:prism_circle)].to_json %>
  target_type: Group
  target_id: <%= ActiveRecord::FixtureSet.identify(:rogue_pack) %>

drift_hidden_in_castle:
  group: castle_clan
  path: <%= [ActiveRecord::FixtureSet.identify(:flux)].to_json %>
  target_type: Profile
  target_id: <%= ActiveRecord::FixtureSet.identify(:drift) %>

ripple_hidden_in_castle:
  group: castle_clan
  path: <%= [ActiveRecord::FixtureSet.identify(:flux)].to_json %>
  target_type: Profile
  target_id: <%= ActiveRecord::FixtureSet.identify(:ripple) %>

static_burst_hidden_in_castle:
  group: castle_clan
  path: <%= [ActiveRecord::FixtureSet.identify(:flux)].to_json %>
  target_type: Group
  target_id: <%= ActiveRecord::FixtureSet.identify(:static_burst) %>
```

Note: `path` is the traversal from root (exclusive) to the group containing the target (inclusive). Rogue Pack is hidden under path `[spectrum, prism_circle]` — meaning "when at Prism Circle reached via Spectrum, hide Rogue Pack." Drift and Ripple are hidden under path `[flux]` — meaning "when at Flux (direct child of Castle Clan), hide these profiles."

### 7c. New fixtures for diamond-path scenario

To test the core path-scoping scenario, add fixtures creating a diamond — Prism Circle reachable via two paths:

**New `group_groups` fixtures** (extend existing file):
```yaml
echo_in_alpha:
  parent_group: alpha_clan
  child_group: echo_shard

prism_in_echo:
  parent_group: echo_shard
  child_group: prism_circle
```

This creates:
```
Alpha Clan
  ├── Spectrum → Prism Circle → Rogue Pack → Stray
  └── Echo Shard → Prism Circle → Rogue Pack → Stray  (same edge, different path)
```

**New `inclusion_overrides` fixture** for path-specific hiding:
```yaml
stray_hidden_in_rogue_pack_via_spectrum:
  group: alpha_clan
  path: <%= [ActiveRecord::FixtureSet.identify(:spectrum), ActiveRecord::FixtureSet.identify(:prism_circle), ActiveRecord::FixtureSet.identify(:rogue_pack)].to_json %>
  target_type: Profile
  target_id: <%= ActiveRecord::FixtureSet.identify(:stray) %>

# No override for path [echo_shard, prism_circle, rogue_pack] → Stray visible there
```

---

## Phase 8: Test Updates

### 8a. Model tests — `group_test.rb`

**Rewrite override-related tests** to use the new model:

- **Hidden group excluded from tree**: Create override hiding Rogue Pack via path `[spectrum, prism_circle]` when viewing Alpha Clan. Assert `alpha_clan.descendant_tree` does not include Rogue Pack under Prism Circle, but `spectrum.descendant_tree` (which has a different root, so no overrides apply) does.
- **Same target hidden along one path but visible along another**: With the diamond fixtures (Prism Circle under both Spectrum and Echo Shard), create override `(alpha_clan, path: [spectrum, prism_circle, rogue_pack], "Profile", stray)`. Assert Stray is absent from Rogue Pack's profiles when reached via Spectrum but present when reached via Echo Shard — within the same `alpha_clan.descendant_tree`.
- **Cascading hide**: Hide Spectrum via path `[]` under Alpha Clan. Assert Prism Circle and Rogue Pack also absent from `alpha_clan.descendant_tree`.
- **Hidden profile**: Create profile override at a specific path. Assert profile absent from tree node's profiles at that path, but present at a different path or in a different root.
- **Management tree**: Assert `management_tree` returns all items with correct `hidden`, `cascade_hidden`, `path`, and `container_path` fields.
- **Stale overrides harmless**: Create an override with a path containing a group that's since been unlinked. Assert it doesn't affect traversal (silently ignored).
- **Remove** tests for: `subgroup_inclusion_mode`, `profile_inclusion_mode`, `selected` mode, old override effective_settings, old edge-contextual overrides.

### 8b. Model tests — `group_group_test.rb`

- Remove all inclusion_mode validation tests
- Keep circular reference, same-user, self-reference tests

### 8c. Model tests — `inclusion_override_test.rb`

- Rewrite for new schema: validates `target_type`, uniqueness scoped to `group_id + path + target_type + target_id`, same-user validation, path-groups-exist validation
- Test cascade delete when root group destroyed (group_id FK)
- Test that empty path `[]` works for root-level items
- Test that the same target can be hidden at one path but not another
- Test path normalisation (strings to integers)

### 8d. Controller tests — `our/groups_controller_test.rb`

- **Remove** tests for: `update_relationship`, `update_override`, `remove_override`
- **Add** tests for `toggle_visibility`:
  - Hide a group (creates override with path)
  - Show a group (destroys override)
  - Hide a profile at a specific path
  - Show a profile
  - Hide a root-level profile (empty path)
  - Invalid target type → error
  - Wrong user's target → not found
  - Path contains group not in tree → not found
  - JSON response format
  - HTML redirect format

### 8e. System tests — `manage_groups_test.rb`

Rewrite to match new UI:

- **Tree renders all groups and profiles**: visit manage_groups, assert all descendant groups and profiles visible in tree
- **Checkbox hides group**: uncheck a group checkbox, verify "hidden" tag appears
- **Cascading hide**: uncheck a parent group, verify children show "hidden" tag and disabled checkboxes
- **Checkbox hides profile**: uncheck a profile checkbox, verify "hidden" tag
- **Path-scoped hiding**: with diamond fixtures, same group appears via two paths — hide a profile via one path, verify it's still visible via the other path in the same tree
- **Public view reflects changes**: hide a group, visit public page, assert group not in sidebar
- **Add/remove group**: add a sub-group, see it in tree; remove it, gone from tree

### 8f. System tests — `group_management_test.rb`

Update public-tree rendering tests to work with the new override data (fixture changes).

---

## Phase 9: Cleanup

### 9a. Remove `inclusion_controller.js`

No longer needed — replaced by `visibility_toggle_controller.js`. Remove the file and its registration in the Stimulus manifest.

### 9b. Simplify Group model

After all tests pass, review the Group model for any dead code from the old system:
- Unused private methods
- Unnecessary complexity in `build_children_map` (no longer needs mode data)
- Potential to merge `descendant_group_ids` and `reachable_group_ids` (they become identical)

---

## Implementation Order

1. **Phase 1** — Migration - ✅ DONE
2. **Phase 2** — Model changes
3. **Phase 7** — Test fixtures
4. **Phase 3** — Routes & controller
5. **Phase 4** — Views
6. **Phase 5** — JavaScript
7. **Phase 6** — CSS
8. **Phase 8** — Tests
9. **Phase 9** — Cleanup

---

## Verification

```sh
bin/rails db:migrate
bin/rails test
bin/rails test:system
bin/rubocop
```

Manual verification:
1. Visit manage_groups for Alpha Clan — see tree with checkboxes
2. Uncheck Rogue Pack (under Prism Circle) — see "hidden" tag, AJAX "Saved" feedback
3. Visit public Alpha Clan page — Rogue Pack not in sidebar under Prism Circle
4. Visit public Spectrum page — Rogue Pack IS in sidebar
5. Uncheck Spectrum — Prism Circle and Rogue Pack cascade-hidden
6. Set up diamond: add Echo Shard under Alpha Clan, add Prism Circle under Echo Shard. Both branches now show Prism Circle → Rogue Pack → Stray. Hide Stray via the Spectrum branch — verify Stray still visible via the Echo Shard branch in the same tree
7. Disable JS, uncheck a group — form submits, page reloads with change applied

---

## Risks & Notes

- **Data migration**: existing `selected` mode edges with specific subgroup/profile lists must be correctly translated to individual `inclusion_override` records with the correct `path`. The migration must walk the tree depth-first, accumulating the path of group IDs at each level. Write a reversible migration with careful mapping.
- **Performance**: the new model queries `inclusion_overrides` per root group (one query for all overrides, loaded into a Set of `[path, target_type, target_id]` tuples). Ruby `Set#include?` with arrays-as-elements is O(1) amortised. Paths are typically short (3–5 elements). This is simpler and likely faster than the current per-edge override loading.
- **Tree traversal for all_profiles**: because overrides are path-scoped, `all_profiles` can no longer use flat set subtraction. It must walk the tree to collect visible profiles, checking overrides at each path. This is still a single pass through the tree with one pre-loaded set of overrides.
- **Cascading in JS vs server**: JS handles visual cascading client-side for responsiveness, but the server is the source of truth. A full page reload always shows the correct state.
- **No "select all" / "deselect all"**: if a group has many profiles, the user must hide them one by one. Hiding the parent group is the bulk alternative. This is a conscious trade-off for simplicity. Can add batch operations later if needed.
- **jsonb equality for uniqueness**: PostgreSQL's btree operator for jsonb compares arrays element-by-element, so `[1,2,3] = [1,2,3]` and `[1,2,3] ≠ [1,3,2]`. This is what we want — path order matters. A single unique index on `(group_id, path, target_type, target_id)` works correctly.
- **Stale overrides**: when a `group_group` edge is removed or a group is deleted, overrides whose paths include that group become unreachable — the tree traversal simply never visits that path, so the overrides are silently ignored. They take up negligible space and can be cleaned up by a periodic task or an `after_destroy` callback. This is a deliberate choice over a FK-based approach, since `path` is a jsonb array, not a series of foreign keys.
- **Path length**: in practice, trees are 3–5 levels deep. The largest reasonable path might be 8–10 IDs (bigints), which is ~80 bytes of jsonb. Well within PostgreSQL performance thresholds.
- **No circular paths**: the existing `no_circular_reference` validation on `GroupGroup` ensures a group can never be its own ancestor, so paths never contain repeated group IDs.
