# Plan: Labels & Duplication for Profiles and Groups

## Summary

Add private **labels** to profiles and groups, visible only on management pages, so users can distinguish different versions of profiles/groups shared with different people. Then add the ability to **duplicate an entire group tree**, assigning new labels to all copies — with an intelligent conflict-resolution wizard when sub-groups or profiles already have copies with the requested label.

The main purpose: share different versions of groups and profiles with different people, and let the owning account identify which is which.

### Key decisions from discussion

- **"Labels"** (not "tags" or "markers") — distinct from the existing fixed-list theme tags
- **Free-form text** — a comma-separated text field in the form; stored as a jsonb array in the database
- **Private only** — labels appear on authenticated management pages (`our/`) and never on public pages
- **Filterable** — the index pages (Our Profiles, Our Groups) get a filter UI to narrow by label
- **Avatar duplication** — when duplicating, the Active Storage avatar is copied to the new record
- **Copy lineage tracking** — a nullable `copied_from_id` self-referencing FK on both profiles and groups, so the system can detect existing copies reliably (survives renames)
- **Group-level duplication only** — no standalone "duplicate a profile" feature; profiles are always copied as part of a group tree duplication
- **Profiles follow the group** — when a sub-group conflict is resolved (reuse existing copy vs. create new), profiles inside follow that decision automatically
- **Overrides on reused copies are left as-is** — when reusing an existing sub-group copy, its inclusion overrides are not modified; only freshly-copied groups get remapped overrides from the source
- **Step-by-step wizard** — conflicts are resolved one at a time before any copying begins; a final confirmation step shows the full plan and executes everything in one transaction

---

## Current state

### Database

- `profiles`: `id`, `name`, `pronouns`, `description`, `heart_emojis` (jsonb), `avatar` (Active Storage), `avatar_alt_text`, `uuid`, `user_id`, timestamps
- `groups`: `id`, `name`, `description`, `avatar` (Active Storage), `avatar_alt_text`, `uuid`, `user_id`, timestamps
- `group_profiles`: join table (`group_id`, `profile_id`)
- `group_groups`: join table (`parent_group_id`, `child_group_id`)
- `inclusion_overrides`: `group_id`, `path` (jsonb), `target_type`, `target_id`

### Behaviour

- Profiles and groups belong to a user. Users CRUD them at `our/profiles` and `our/groups`.
- Each profile/group gets a unique UUID for public sharing. Internal integer IDs are used in authenticated routes.
- Groups form a recursive tree via `GroupGroup`. `InclusionOverride` records hide specific items at specific paths.
- There is no duplication feature and no label/marker field on either model.

---

## Phase 1: Labels data layer

### Migration

Add a `labels` jsonb column to both `profiles` and `groups`:

```ruby
class AddLabelsToProfilesAndGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :profiles, :labels, :jsonb, default: [], null: false
    add_column :groups, :labels, :jsonb, default: [], null: false
  end
end
```

### Model concern — `HasLabels`

Create `app/models/concerns/has_labels.rb`:

```ruby
module HasLabels
  extend ActiveSupport::Concern

  included do
    before_validation :normalize_labels
  end

  # Accept a comma-separated string or array and persist as a clean array.
  def labels_text
    labels.join(", ")
  end

  def labels_text=(value)
    self.labels = value.to_s.split(",").map(&:strip).reject(&:blank?).uniq
  end

  private

  def normalize_labels
    self.labels = Array(labels).map { |l| l.to_s.strip }.reject(&:blank?).uniq
  end
end
```

Include in both `Profile` and `Group`:

```ruby
class Profile < ApplicationRecord
  include HasAvatar
  include HasLabels
  # ...
end

class Group < ApplicationRecord
  include HasAvatar
  include HasLabels
  # ...
end
```

### Tests

- Unit tests that `labels_text=` parses comma-separated strings correctly (trims whitespace, deduplicates, rejects blanks).
- Unit tests that `normalize_labels` cleans up arrays on validation.
- Unit tests that `labels_text` round-trips correctly.

---

## Phase 2: Labels in profile forms and views

### Form

Add a labels text field to `app/views/our/profiles/_form.html.haml`, above the description field:

```haml
.form-group
  = form.label :labels_text, "Labels (private, comma-separated)"
  = form.text_field :labels_text, value: profile.labels_text, placeholder: "e.g. safe, work, close friends"
  %p.form-hint Labels are only visible to you — they never appear on shared pages.
```

### Controller

Permit `labels_text` in `Our::ProfilesController#profile_params`:

```ruby
params.require(:profile).permit(:name, :pronouns, :description, :avatar, :avatar_alt_text, :created_at, :labels_text, group_ids: [], heart_emojis: [])
```

### Private show page

Display labels on `app/views/our/profiles/show.html.haml`, in the card header area (near the name/pronouns), styled as small inline badges:

```haml
- if @profile.labels.any?
  .label-badges
    - @profile.labels.each do |label|
      %span.label-badge= label
```

### Private index page

Display labels on profile cards in `app/views/our/profiles/index.html.haml`:

```haml
- if profile.labels.any?
  .label-badges
    - profile.labels.each do |label|
      %span.label-badge= label
```

### CSS

Add label badge styles to `application.css`:

```css
.label-badges {
  display: flex;
  flex-wrap: wrap;
  gap: 0.25rem;
}

.label-badge {
  display: inline-block;
  padding: 0.125rem 0.5rem;
  border-radius: 999px;
  font-size: 0.75rem;
  background: color-mix(in srgb, var(--primary-button-bg) 20%, transparent);
  color: var(--text);
  border: 1px solid color-mix(in srgb, var(--primary-button-bg) 40%, transparent);
}
```

Add `@media (forced-colors: active)` support for the badge:

```css
@media (forced-colors: active) {
  .label-badge {
    border: 1px solid ButtonText;
  }
}
```

### Public pages — no change

Confirm that `app/views/profiles/show.html.haml` and `app/views/groups/show.html.haml` (the public controllers) do NOT reference labels. No code changes needed; just verify.

### Tests

- Controller test: create a profile with `labels_text: "safe, work"` and verify it persists as `["safe", "work"]`.
- Controller test: update labels and verify the change.
- System test: verify labels appear on private show/index pages.
- System test (or controller test): verify labels do NOT appear on the public profile page.

---

## Phase 3: Labels in group forms and views

Same pattern as Phase 2, but for groups.

### Form

Add labels text field to `app/views/our/groups/_form.html.haml`:

```haml
.form-group
  = form.label :labels_text, "Labels (private, comma-separated)"
  = form.text_field :labels_text, value: group.labels_text, placeholder: "e.g. safe, work, close friends"
  %p.form-hint Labels are only visible to you — they never appear on shared pages.
```

### Controller

Permit `labels_text` in `Our::GroupsController#group_params`:

```ruby
params.require(:group).permit(:name, :description, :avatar, :avatar_alt_text, :created_at, :labels_text)
```

### Private show and index pages

Display label badges on the group show page and index page cards, same markup and styling as profiles.

### Tests

- Controller tests for label CRUD on groups.
- System tests for label display on private pages.
- Verify labels don't appear on public group pages.

---

## Phase 4: Filtering by label

### Index pages

Add a label filter above the card list on both `Our::Profiles#index` and `Our::Groups#index`.

#### Controller changes

In `Our::ProfilesController#index`:

```ruby
def index
  @profiles = Current.user.profiles.order(:name)
  if params[:label].present?
    @profiles = @profiles.where("labels @> ?", [params[:label]].to_json)
  end
  @all_labels = Current.user.profiles.pluck(:labels).flatten.uniq.sort
end
```

Same pattern for `Our::GroupsController#index`.

#### View changes

Add a filter bar at the top of the index page:

```haml
- if @all_labels.any?
  .filter-bar
    %span.filter-bar__label Filter by label:
    = link_to "All", our_profiles_path, class: "btn btn--small #{'btn--active' unless params[:label]}"
    - @all_labels.each do |label|
      = link_to label, our_profiles_path(label: label), class: "btn btn--small #{'btn--active' if params[:label] == label}"
```

#### CSS

Add filter bar styles:

```css
.filter-bar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.5rem;
  margin-bottom: 1rem;
}

.filter-bar__label {
  font-size: 0.875rem;
  color: var(--input-label);
}

.btn--active {
  background: var(--primary-button-bg);
  color: var(--primary-button-text);
}
```

### Tests

- Controller tests: verify filtering returns only matching profiles/groups.
- System test: click a label filter and see the list narrow.

---

## Phase 5: Copy lineage data layer

Before duplication can work intelligently, we need to track which records are copies of which originals. This allows the conflict-resolution wizard to detect "Prism Circle already has a copy with label blue".

### Migration

Add a nullable `copied_from_id` self-referencing FK to both `profiles` and `groups`:

```ruby
class AddCopiedFromToProfilesAndGroups < ActiveRecord::Migration[8.1]
  def change
    add_reference :profiles, :copied_from, null: true, foreign_key: { to_table: :profiles }
    add_reference :groups, :copied_from, null: true, foreign_key: { to_table: :groups }
  end
end
```

### Model associations

```ruby
class Profile < ApplicationRecord
  belongs_to :copied_from, class_name: "Profile", optional: true
  has_many :copies, class_name: "Profile", foreign_key: :copied_from_id, dependent: :nullify
  # ...
end

class Group < ApplicationRecord
  belongs_to :copied_from, class_name: "Group", optional: true
  has_many :copies, class_name: "Group", foreign_key: :copied_from_id, dependent: :nullify
  # ...
end
```

`dependent: :nullify` means deleting an original just clears the link on its copies — copies are never auto-deleted.

### Model helper — finding existing copies by label

Add a method to both models (or the `HasLabels` concern):

```ruby
# Returns copies of this record that have ALL of the given labels.
def copies_with_labels(labels)
  copies.where("labels @> ?", labels.to_json)
end
```

### Tests

- Unit test: `copied_from` / `copies` association works correctly.
- Unit test: `copies_with_labels` returns matching copies and excludes non-matching.
- Unit test: deleting an original nullifies `copied_from_id` on copies.

---

## Phase 6: Duplicate a group (deep copy with conflict-resolution wizard)

This is the most complex and most powerful phase. Duplicating a group means deep-copying the entire tree of sub-groups, profiles, and inclusion overrides — but with intelligent handling of items that already have copies with the requested label.

### The problem

Consider the test data tree for user three:

```
Alpha Clan
├── Spectrum
│   └── Prism Circle
│       └── Rogue Pack
│           └── Stray (profile)
├── Echo Shard
│   └── Prism Circle  (diamond — same group)
│       └── Rogue Pack
└── Grove (profile)

Castle Clan
├── Flux
│   ├── Echo Shard
│   │   └── Prism Circle
│   │       └── Rogue Pack
│   ├── Static Burst
│   └── Drift, Ripple (profiles)
├── Castle Flux
└── Shadow (profile)
```

**Scenario 1:** Duplicate "Echo Shard" with label "blue". This creates:
- Echo Shard (blue) — new copy
  - Prism Circle (blue) — new copy
    - Rogue Pack (blue) — new copy
- All profiles inside also get copied with label "blue"
- Inclusion overrides scoped to Echo Shard are copied with remapped paths

**Scenario 2 (later):** Duplicate "Spectrum" with label "blue". The wizard traverses down and finds:
- Spectrum itself → no existing copy with "blue" → will be freshly copied
- Prism Circle → **already has a copy with label "blue"** (from Scenario 1)
- Rogue Pack → **already has a copy with label "blue"** (from Scenario 1)

The wizard must ask the user what to do about Prism Circle and Rogue Pack.

### Wizard flow — step by step

The duplication uses a multi-step wizard. No actual copying happens until the final confirmation.

#### Step 1: Initiate — labels input

The user clicks "Duplicate" on a group's show page. They see a form:

- **Labels for all copies** (comma-separated text field)
- A brief description: "This will copy [Group Name] and its entire tree of sub-groups and profiles. Every new copy will be given these labels."
- **Next** button

On submission, the controller scans the tree to identify conflicts (sub-groups and profiles that already have a copy with ALL of the specified labels). If there are no conflicts, skip straight to the confirmation step.

#### Step 2: Conflict resolution (one per conflict)

For each conflicting item, the user sees a dedicated page showing:

- A heading: "[Item Name] already has a copy with label \"blue\""
- **Side-by-side comparison:**
  - **Left card — Original:** The source item being copied (name, labels, description snippet, avatar thumbnail)
  - **Right card — Existing copy:** The already-existing copy that has the requested label (name, labels, description snippet, avatar thumbnail)
- **Two choices** (radio buttons):
  - **"Use the existing copy"** — link the existing copy into the new tree structure instead of making a fresh one. Its profiles and overrides stay as they are.
  - **"Create a new copy"** — ignore the existing copy and make a fresh duplicate of the original.
- **Next** button to proceed to the next conflict, or to confirmation if this was the last one.

Profiles follow the group decision: if the user chooses to reuse an existing group copy, all profiles inside that group are also reused as-is. If they choose to create a new group copy, all profiles inside are freshly copied. Profiles are never presented as separate conflict choices.

The conflict resolution order should be **depth-first**, matching the tree structure, so the user resolves parent groups before their children. If a parent group is reused, its children are implicitly reused too (they're already part of the existing copy) — so those child conflicts are skipped.

**State management:** The wizard stores conflict resolutions in the session (or as hidden form fields accumulated across steps). A `conflict_resolutions` hash maps `{original_id => "reuse" | "copy"}` for each group conflict.

#### Step 3: Confirmation

A summary page showing the full plan:

- "The following items will be **created as new copies** with label(s) [labels]:" — list of groups and profiles being freshly copied
- "The following existing copies will be **linked into the new tree**:" — list of groups (and their profiles) being reused
- **Confirm & duplicate** button
- **Back** link (returns to Step 1 to start over)

Only when the user clicks **Confirm & duplicate** does the actual copying happen.

### Routes

```ruby
resources :our_groups, path: "our/groups", controller: "our/groups" do
  member do
    # ... existing actions ...
    get  :duplicate           # Step 1: labels input form
    post :duplicate_scan      # Processes Step 1, redirects to resolve or confirm
    get  :duplicate_resolve   # Step 2: shows one conflict at a time
    post :duplicate_resolve   # Processes one conflict choice, advances to next
    get  :duplicate_confirm   # Step 3: summary of planned actions
    post :duplicate_execute   # Performs the actual duplication
  end
end
```

### Session-based wizard state

Store the wizard state in the session under a key like `duplication_wizard`:

```ruby
session[:duplication_wizard] = {
  source_group_id: @source.id,
  labels: ["blue"],
  conflicts: [
    # Ordered depth-first. Each entry:
    { original_id: 42, original_type: "Group", name: "Prism Circle",
      existing_copy_id: 99, existing_copy_name: "Prism Circle",
      existing_copy_labels: ["blue"] },
    # ...
  ],
  resolutions: {},          # filled in as user resolves: { "42" => "reuse" }
  current_conflict_index: 0 # which conflict we're showing
}
```

### Model method — `Group#scan_for_conflicts`

Scans the tree and returns an array of conflicts:

```ruby
# Returns an array of hashes describing sub-groups (and only sub-groups)
# that already have copies with ALL of the given labels.
# Ordered depth-first to match tree traversal.
def scan_for_conflicts(labels)
  conflicts = []
  # Walk descendant groups depth-first
  walk_tree_depth_first do |group|
    existing = group.copies_with_labels(labels).first
    if existing
      conflicts << {
        original_id: group.id,
        original_type: "Group",
        name: group.name,
        existing_copy_id: existing.id,
        existing_copy_name: existing.name,
        existing_copy_labels: existing.labels
      }
    end
  end
  conflicts
end
```

### Model method — `Group#deep_duplicate`

The deep_duplicate method now accepts a resolutions hash:

```ruby
# Deep-copies this group and its entire tree.
#
# resolutions: a Hash of { original_group_id => "reuse" | "copy" }
#   - "reuse": link the existing copy into the new tree instead of copying
#   - "copy" (or absent): create a fresh copy
#
# For reused groups:
#   - Their profiles and overrides are left as-is
#   - They are linked as children in the new tree structure
#
# For freshly copied groups:
#   - New UUID, new labels, avatar copied
#   - All profiles inside are freshly copied
#   - Inclusion overrides are recreated with remapped paths
#   - copied_from_id is set to the original's ID
#
# Everything happens in a single transaction.
def deep_duplicate(new_labels: [], resolutions: {})
  group_map = {}   # old_id => new_or_reused_group
  profile_map = {} # old_id => new_or_reused_profile
  reused_group_ids = Set.new

  groups_to_process = Group.where(id: reachable_group_ids, user_id: user_id)
                           .includes(:profiles, avatar_attachment: :blob)

  # Phase A: Build group map, respecting resolutions
  groups_to_process.each do |original_group|
    resolution = resolutions[original_group.id.to_s]
    if resolution == "reuse"
      existing_copy = original_group.copies_with_labels(new_labels).first
      if existing_copy
        group_map[original_group.id] = existing_copy
        reused_group_ids << original_group.id
        # Also mark all descendants of this reused group as implicitly reused
        # (they're already part of the existing copy's tree)
        next
      end
    end

    # Fresh copy
    new_group = original_group.dup
    new_group.uuid = PluralProfilesUuid.generate
    new_group.labels = new_labels
    new_group.copied_from = original_group
    group_map[original_group.id] = new_group
  end

  # Skip groups that are descendants of reused groups
  # (their subtrees already exist in the reused copy)
  skip_ids = Set.new
  reused_group_ids.each do |rid|
    original = groups_to_process.find { |g| g.id == rid }
    original&.descendant_group_ids&.each { |did| skip_ids << did }
  end
  skip_ids.each { |sid| group_map.delete(sid) unless reused_group_ids.include?(sid) }

  # Phase B: Build profile map for freshly-copied groups only
  fresh_group_ids = group_map.keys - reused_group_ids.to_a
  profile_ids = GroupProfile.where(group_id: fresh_group_ids)
                            .pluck(:profile_id).uniq
  Profile.where(id: profile_ids, user_id: user_id)
         .includes(avatar_attachment: :blob).each do |original_profile|
    new_profile = original_profile.dup
    new_profile.uuid = PluralProfilesUuid.generate
    new_profile.labels = new_labels
    new_profile.copied_from = original_profile
    profile_map[original_profile.id] = new_profile
  end

  # Phase C: Execute everything in a transaction
  ActiveRecord::Base.transaction do
    # Save new groups (skip reused — they already exist)
    group_map.each do |old_id, group|
      group.save! if group.new_record?
    end
    profile_map.each_value(&:save!)

    # Copy avatars for new records
    group_map.each do |old_id, new_group|
      next if reused_group_ids.include?(old_id)
      original = groups_to_process.find { |g| g.id == old_id }
      duplicate_avatar(original, new_group) if original&.avatar&.attached?
    end
    profile_map.each do |old_id, new_profile|
      original = Profile.find(old_id)
      duplicate_avatar(original, new_profile) if original.avatar.attached?
    end

    # Recreate group_groups edges (only for non-skipped groups)
    GroupGroup.where(parent_group_id: group_map.keys,
                     child_group_id: group_map.keys).each do |gg|
      next if skip_ids.include?(gg.parent_group_id) || skip_ids.include?(gg.child_group_id)
      GroupGroup.create!(
        parent_group: group_map[gg.parent_group_id],
        child_group: group_map[gg.child_group_id]
      )
    end

    # Recreate group_profiles for freshly-copied groups
    GroupProfile.where(group_id: fresh_group_ids).each do |gp|
      next unless group_map[gp.group_id] && profile_map[gp.profile_id]
      GroupProfile.create!(
        group: group_map[gp.group_id],
        profile: profile_map[gp.profile_id]
      )
    end

    # Recreate inclusion overrides for freshly-copied groups only
    # (reused groups keep their existing overrides)
    InclusionOverride.where(group_id: fresh_group_ids).each do |override|
      new_root = group_map[override.group_id]
      next unless new_root

      new_path = override.path.map { |gid| group_map[gid]&.id }.compact
      next if new_path.length != override.path.length

      new_target_id = case override.target_type
                      when "Group"   then group_map[override.target_id]&.id
                      when "Profile" then profile_map[override.target_id]&.id
                      end
      next unless new_target_id

      InclusionOverride.create!(
        group: new_root,
        path: new_path,
        target_type: override.target_type,
        target_id: new_target_id
      )
    end
  end

  group_map[id] # Return the new root group
end
```

### Controller — wizard actions

```ruby
# Step 1: Show label input form
def duplicate
  @source = Current.user.groups.find_by!(uuid: params[:id])
end

# Process Step 1: scan for conflicts and redirect
def duplicate_scan
  @source = Current.user.groups.find_by!(uuid: params[:id])
  labels = params[:labels_text].to_s.split(",").map(&:strip).reject(&:blank?).uniq

  if labels.empty?
    flash.now[:alert] = "Please enter at least one label for the copies."
    render :duplicate, status: :unprocessable_entity
    return
  end

  conflicts = @source.scan_for_conflicts(labels)

  session[:duplication_wizard] = {
    source_group_id: @source.id,
    labels: labels,
    conflicts: conflicts,
    resolutions: {},
    current_conflict_index: 0
  }

  if conflicts.empty?
    redirect_to duplicate_confirm_our_group_path(@source)
  else
    redirect_to duplicate_resolve_our_group_path(@source)
  end
end

# Step 2: Show one conflict at a time
def duplicate_resolve
  @source = Current.user.groups.find_by!(uuid: params[:id])
  wizard = session[:duplication_wizard]
  index = wizard["current_conflict_index"]
  @conflict = wizard["conflicts"][index]
  @conflict_number = index + 1
  @total_conflicts = wizard["conflicts"].length
  @original = Group.find(@conflict["original_id"])
  @existing_copy = Group.find(@conflict["existing_copy_id"])
  @labels = wizard["labels"]
end

# Process one conflict resolution and advance
def duplicate_resolve_post
  @source = Current.user.groups.find_by!(uuid: params[:id])
  wizard = session[:duplication_wizard]
  index = wizard["current_conflict_index"]
  conflict = wizard["conflicts"][index]

  # Record the user's choice
  wizard["resolutions"][conflict["original_id"].to_s] = params[:resolution] # "reuse" or "copy"

  # If user chose "reuse", skip conflicts for descendants of this group
  if params[:resolution] == "reuse"
    reused_group = Group.find(conflict["original_id"])
    descendant_ids = reused_group.descendant_group_ids.map(&:to_s).to_set
    # Mark descendant conflicts as implicitly resolved
    wizard["conflicts"].each_with_index do |c, i|
      next if i <= index
      if descendant_ids.include?(c["original_id"].to_s)
        wizard["resolutions"][c["original_id"].to_s] = "reuse"
      end
    end
  end

  # Find next unresolved conflict
  next_index = (index + 1...wizard["conflicts"].length).find do |i|
    !wizard["resolutions"].key?(wizard["conflicts"][i]["original_id"].to_s)
  end

  if next_index
    wizard["current_conflict_index"] = next_index
    session[:duplication_wizard] = wizard
    redirect_to duplicate_resolve_our_group_path(@source)
  else
    session[:duplication_wizard] = wizard
    redirect_to duplicate_confirm_our_group_path(@source)
  end
end

# Step 3: Show confirmation summary
def duplicate_confirm
  @source = Current.user.groups.find_by!(uuid: params[:id])
  wizard = session[:duplication_wizard]
  @labels = wizard["labels"]
  @conflicts = wizard["conflicts"]
  @resolutions = wizard["resolutions"]

  # Build lists for the summary
  all_group_ids = @source.reachable_group_ids
  reused_ids = @resolutions.select { |_, v| v == "reuse" }.keys.map(&:to_i).to_set

  # Groups being reused also implicitly reuse their descendants
  expanded_reused_ids = Set.new(reused_ids)
  reused_ids.each do |rid|
    Group.find(rid).descendant_group_ids.each { |did| expanded_reused_ids << did }
  end

  @groups_to_copy = Group.where(id: all_group_ids - expanded_reused_ids.to_a)
  @groups_to_reuse = Group.where(id: expanded_reused_ids.to_a)
                          .map { |g| [g, g.copies_with_labels(@labels).first] }
                          .reject { |_, copy| copy.nil? }
end

# Execute the duplication
def duplicate_execute
  @source = Current.user.groups.find_by!(uuid: params[:id])
  wizard = session[:duplication_wizard]
  labels = wizard["labels"]
  resolutions = wizard["resolutions"]

  @group = @source.deep_duplicate(new_labels: labels, resolutions: resolutions)
  session.delete(:duplication_wizard)
  redirect_to our_group_path(@group), notice: "Group duplicated with all sub-groups and profiles."
end
```

### View — Step 1: `app/views/our/groups/duplicate.html.haml`

```haml
- content_for(:title) { "Duplicate #{@source.name} — Plural Profiles" }

%h1 Duplicate group

.card
  %p
    You are duplicating
    %strong= @source.name
    and its entire tree of sub-groups and profiles. Every new copy will be
    given the labels you specify below.

  = form_with url: duplicate_scan_our_group_path(@source), method: :post do |form|
    .form-group
      = form.label :labels_text, "Labels for all copies (private, comma-separated)"
      = form.text_field :labels_text, placeholder: "e.g. work, public"
      %p.form-hint At least one label is required so copies can be identified.

    .form-actions
      = form.submit "Next", class: "btn"
      = link_to "Cancel", our_group_path(@source), class: "btn btn--secondary"
```

### View — Step 2: `app/views/our/groups/duplicate_resolve.html.haml`

```haml
- content_for(:title) { "Resolve conflict — Plural Profiles" }

%h1 Conflict #{@conflict_number} of #{@total_conflicts}

.card
  %p
    %strong= @original.name
    already has a copy with the label
    - @labels.each do |label|
      %span.label-badge= label

  .duplicate-comparison
    .duplicate-comparison__card
      %h3 Original
      .duplicate-comparison__item
        - if @original.avatar.attached?
          = image_tag @original.avatar, class: "avatar avatar--small"
        %strong= @original.name
        - if @original.labels.any?
          .label-badges
            - @original.labels.each do |l|
              %span.label-badge= l
        %p.duplicate-comparison__description= truncate(@original.description, length: 120)

    .duplicate-comparison__card
      %h3 Existing copy
      .duplicate-comparison__item
        - if @existing_copy.avatar.attached?
          = image_tag @existing_copy.avatar, class: "avatar avatar--small"
        %strong= @existing_copy.name
        - if @existing_copy.labels.any?
          .label-badges
            - @existing_copy.labels.each do |l|
              %span.label-badge= l
        %p.duplicate-comparison__description= truncate(@existing_copy.description, length: 120)

  = form_with url: duplicate_resolve_our_group_path(@source), method: :post do |form|
    .form-group
      .radio-group
        = form.radio_button :resolution, "reuse", id: "resolution_reuse"
        = form.label :resolution, "Use the existing copy", for: "resolution_reuse"
        %p.form-hint The existing copy and all its contents will be linked into your new tree as-is.

      .radio-group
        = form.radio_button :resolution, "copy", id: "resolution_copy"
        = form.label :resolution, "Create a new copy", for: "resolution_copy"
        %p.form-hint A brand new copy will be made from the original, ignoring the existing copy.

    .form-actions
      = form.submit "Next", class: "btn"
```

### View — Step 3: `app/views/our/groups/duplicate_confirm.html.haml`

```haml
- content_for(:title) { "Confirm duplication — Plural Profiles" }

%h1 Confirm duplication

.card
  %p
    Duplicating
    %strong= @source.name
    with label(s):
    - @labels.each do |label|
      %span.label-badge= label

  - if @groups_to_copy.any?
    %h3 Will be created as new copies
    %ul
      - @groups_to_copy.each do |group|
        %li= group.name

  - if @groups_to_reuse.any?
    %h3 Existing copies will be linked into the new tree
    %ul
      - @groups_to_reuse.each do |original, copy|
        %li
          = original.name
          %span.text-muted → using
          = copy.name
          - if copy.labels.any?
            .label-badges
              - copy.labels.each do |l|
                %span.label-badge= l

  = form_with url: duplicate_execute_our_group_path(@source), method: :post do |form|
    .form-actions
      = form.submit "Confirm & duplicate", class: "btn"
      = link_to "Start over", duplicate_our_group_path(@source), class: "btn btn--secondary"
```

### CSS additions

```css
.duplicate-comparison {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1rem;
  margin: 1rem 0;
}

.duplicate-comparison__card {
  padding: 1rem;
  border: 1px solid var(--pane-border);
  border-radius: 0.5rem;
  background: var(--pane-bg);
}

.duplicate-comparison__item {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.duplicate-comparison__description {
  font-size: 0.875rem;
  color: var(--text);
  opacity: 0.8;
}

.radio-group {
  margin-bottom: 0.75rem;
}

.radio-group input[type="radio"] {
  margin-right: 0.5rem;
}

@media (max-width: 600px) {
  .duplicate-comparison {
    grid-template-columns: 1fr;
  }
}

@media (forced-colors: active) {
  .duplicate-comparison__card {
    border-color: ButtonText;
  }
}
```

### Button on show page

Add a "Duplicate" button to group actions in `app/views/our/groups/show.html.haml`:

```haml
= link_to "Duplicate", duplicate_our_group_path(@group), class: "btn btn--secondary"
```

### Avatar helper

Extract a shared `duplicate_avatar` method (used by the model's `deep_duplicate`):

```ruby
# In a concern or helper shared between controllers and models
def duplicate_avatar(source, target)
  return unless source.avatar.attached?
  source.avatar.blob.open do |tmp|
    target.avatar.attach(
      io: tmp,
      filename: source.avatar.blob.filename,
      content_type: source.avatar.blob.content_type
    )
  end
end
```

### Tests

**Model tests:**
- `scan_for_conflicts` returns correct conflicts for a tree with existing labeled copies.
- `scan_for_conflicts` returns empty array when no copies exist.
- `deep_duplicate` with no conflicts creates correct number of groups, profiles, edges, and overrides.
- `deep_duplicate` with `resolutions: { id => "reuse" }` links the existing copy instead of creating a new one.
- `deep_duplicate` with reused parent skips its descendants (doesn't create duplicate edges).
- Profiles appearing in multiple freshly-copied sub-groups are copied once and linked to all.
- Inclusion overrides have correctly remapped paths and target IDs for fresh copies.
- Inclusion overrides are NOT modified on reused copies.
- All freshly-copied records have `copied_from_id` set.
- All freshly-copied records have new UUIDs and the specified labels.

**Controller tests:**
- `duplicate_scan` with no conflicts redirects to confirm.
- `duplicate_scan` with conflicts redirects to resolve.
- `duplicate_resolve` shows the correct conflict.
- `duplicate_resolve` POST with "reuse" skips descendant conflicts.
- `duplicate_execute` creates the tree and redirects.
- `duplicate_execute` clears the session wizard state.

**System tests:**
- End-to-end: duplicate a group with no conflicts (straight to confirm).
- End-to-end: duplicate a group with conflicts, resolve each one, confirm.
- End-to-end: reuse an existing copy and verify descendants are skipped.

---

## Concrete walkthrough with test data

To make the design concrete, here's exactly what happens with user three's groups:

### Round 1: Duplicate "Echo Shard" → label "blue"

1. User clicks Duplicate on Echo Shard, enters label "blue", clicks Next.
2. `scan_for_conflicts(["blue"])` walks Echo Shard's tree:
   - Echo Shard → no copy with "blue" (it's the source itself, not checked)
   - Prism Circle → no copy with "blue" ✓
   - Rogue Pack → no copy with "blue" ✓
3. No conflicts → skip to confirmation.
4. Confirmation shows: "Will copy: Echo Shard, Prism Circle, Rogue Pack, plus profiles: Mirage, Stray, Ember"
5. User confirms. Result:
   - Echo Shard (blue) `copied_from: Echo Shard`
   - Prism Circle (blue) `copied_from: Prism Circle`
   - Rogue Pack (blue) `copied_from: Rogue Pack`
   - Mirage (blue), Stray (blue), Ember (blue) — all with `copied_from` set
   - All edges and overrides recreated in the new tree

### Round 2: Duplicate "Spectrum" → label "blue"

1. User clicks Duplicate on Spectrum, enters label "blue", clicks Next.
2. `scan_for_conflicts(["blue"])` walks Spectrum's tree:
   - Spectrum → no copy with "blue" ✓
   - Prism Circle → **has copy with "blue"** (Prism Circle (blue) from Round 1)
   - Rogue Pack → **has copy with "blue"** (Rogue Pack (blue) from Round 1)
3. Two conflicts found. Wizard begins.
4. **Conflict 1/2: Prism Circle** — user sees original Prism Circle on the left, Prism Circle (blue) on the right.
   - If user chooses **"Use existing copy"**: Rogue Pack conflict is auto-resolved (it's a descendant of Prism Circle). → Skip to confirmation.
   - If user chooses **"Create new copy"**: advance to Conflict 2.
5. **Conflict 2/2: Rogue Pack** (only shown if user chose "Create new copy" for Prism Circle).
6. Confirmation summary shows the final plan. User confirms.

---

## Phase summary

| Phase | What                                    | Key files changed                                                                |
| ----- | --------------------------------------- | -------------------------------------------------------------------------------- |
| 1     | Labels data layer (migration + concern) | migration, `HasLabels` concern, `Profile`, `Group`                               |
| 2     | Labels in profile forms and views       | `our/profiles/_form`, `our/profiles/show`, `our/profiles/index`, controller, CSS |
| 3     | Labels in group forms and views         | `our/groups/_form`, `our/groups/show`, `our/groups/index`, controller, CSS       |
| 4     | Filtering by label on index pages       | Both index views, both controllers, CSS                                          |
| 5     | Copy lineage data layer                 | Migration, model associations, `copies_with_labels` helper                       |
| 6     | Duplicate a group (wizard + deep copy)  | Routes, controller (wizard actions), model methods, 3 views, CSS                 |

Phases 1–4 are done. Phase 5 is a small data-layer prerequisite. Phase 6 is the main feature and depends on Phase 5.
