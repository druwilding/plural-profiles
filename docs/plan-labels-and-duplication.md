# Plan: Labels & Duplication for Profiles and Groups

## Summary

Add private **labels** to profiles and groups, visible only on management pages, so users can distinguish different versions of profiles/groups shared with different people. Then add the ability to **duplicate** a profile or an entire group tree, assigning new labels to the copies.

### Key decisions from discussion

- **"Labels"** (not "tags" or "markers") — distinct from the existing fixed-list theme tags
- **Free-form text** — a comma-separated text field in the form; stored as a jsonb array in the database
- **Private only** — labels appear on authenticated management pages (`our/`) and never on public pages
- **Filterable** — the index pages (Our Profiles, Our Groups) get a filter UI to narrow by label
- **Avatar duplication** — when duplicating, the Active Storage avatar is copied to the new record
- **Profile deduplication on group deep copy** — when deep-copying a group tree, each profile is copied once and linked to all relevant sub-groups (mirrors the original structure)

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

## Phase 5: Duplicate a profile

### Route

Add a `duplicate` member action to `our_profiles`:

```ruby
resources :our_profiles, path: "our/profiles", controller: "our/profiles" do
  member do
    delete :remove_from_group
    patch :regenerate_uuid
    get :duplicate       # shows the duplicate form
    post :duplicate      # creates the duplicate
  end
end
```

Alternatively, use `get :new_duplicate` and `post :create_duplicate` for clarity. The choice is between REST-ish naming and simplicity. A single `duplicate` action handling both GET and POST is simpler.

### Controller

```ruby
def duplicate
  @source = Current.user.profiles.find_by!(uuid: params[:id])
  if request.post?
    @profile = @source.dup
    @profile.assign_attributes(
      uuid: PluralProfilesUuid.generate,
      labels_text: params[:labels_text].to_s
    )
    duplicate_avatar(@source, @profile) if @source.avatar.attached?

    if @profile.save
      # Copy group memberships
      @source.group_profiles.each do |gp|
        @profile.group_profiles.create(group_id: gp.group_id)
      end
      redirect_to our_profile_path(@profile), notice: "Profile duplicated."
    else
      render :duplicate, status: :unprocessable_entity
    end
  end
end

private

def duplicate_avatar(source, target)
  source.avatar.blob.open do |tmp|
    target.avatar.attach(
      io: tmp,
      filename: source.avatar.blob.filename,
      content_type: source.avatar.blob.content_type
    )
  end
end
```

### View — `app/views/our/profiles/duplicate.html.haml`

```haml
- content_for(:title) { "Duplicate #{@source.name} — Plural Profiles" }

%h1 Duplicate profile

.card
  %p
    You are duplicating
    %strong= @source.name
    \. The new profile will be an exact copy with a new share URL.

  = form_with url: duplicate_our_profile_path(@source), method: :post do |form|
    .form-group
      = form.label :labels_text, "Labels for the new copy (private, comma-separated)"
      = form.text_field :labels_text, value: params[:labels_text], placeholder: "e.g. work, public"
      %p.form-hint These labels replace the original's labels. Leave blank for no labels.

    .form-group
      = form.submit "Create duplicate"
      = link_to "Cancel", our_profile_path(@source), class: "btn btn--secondary"

%p= link_to "← Back to profile", our_profile_path(@source)
```

### Button on show page

Add a "Duplicate" button to the profile actions area in `app/views/our/profiles/show.html.haml`:

```haml
= link_to "Duplicate", duplicate_our_profile_path(@profile), class: "btn btn--secondary"
```

### Tests

- Controller test: POST duplicate creates a new profile with the same attributes, new UUID, and specified labels.
- Controller test: avatar is copied.
- Controller test: group memberships are copied.
- System test: duplicate flow end-to-end.

---

## Phase 6: Duplicate a group (deep copy)

This is the most complex phase. Duplicating a group means deep-copying the entire tree of sub-groups, profiles, and inclusion overrides.

### Route

```ruby
resources :our_groups, path: "our/groups", controller: "our/groups" do
  member do
    # ... existing actions ...
    get :duplicate
    post :duplicate
  end
end
```

### Model method — `Group#deep_duplicate`

Add a method to `Group` that performs the deep copy and returns the new root group:

```ruby
# Deep-copies this group, all descendant groups, all profiles in the tree,
# and all inclusion overrides. Each copied record gets a new UUID and the
# specified labels. Profiles that appear in multiple sub-groups are copied
# once and linked everywhere.
#
# Returns the new root group (unsaved if any errors occur).
def deep_duplicate(new_labels: [])
  # 1. Build a mapping of old group IDs → new Group records
  group_map = {}   # old_id => new_group
  profile_map = {} # old_id => new_profile

  # 2. Walk the tree (BFS or DFS using descendant_group_ids)
  #    For each group: dup attributes, assign new UUID, set labels, copy avatar
  groups_to_copy = Group.where(id: reachable_group_ids, user_id: user_id)
                        .includes(:profiles, avatar_attachment: :blob)

  groups_to_copy.each do |original_group|
    new_group = original_group.dup
    new_group.uuid = PluralProfilesUuid.generate
    new_group.labels = new_labels
    group_map[original_group.id] = new_group
  end

  # 3. For each profile in the tree: dup once, assign new UUID, set labels, copy avatar
  profile_ids = GroupProfile.where(group_id: reachable_group_ids).pluck(:profile_id).uniq
  Profile.where(id: profile_ids, user_id: user_id)
         .includes(avatar_attachment: :blob).each do |original_profile|
    new_profile = original_profile.dup
    new_profile.uuid = PluralProfilesUuid.generate
    new_profile.labels = new_labels
    profile_map[original_profile.id] = new_profile
  end

  # 4. Save all new groups and profiles in a transaction
  ActiveRecord::Base.transaction do
    group_map.each_value(&:save!)
    profile_map.each_value(&:save!)

    # 5. Copy avatars (after save so records have IDs)
    group_map.each do |old_id, new_group|
      original = groups_to_copy.find { |g| g.id == old_id }
      duplicate_avatar(original, new_group) if original.avatar.attached?
    end
    profile_map.each do |old_id, new_profile|
      original = Profile.find(old_id)
      duplicate_avatar(original, new_profile) if original.avatar.attached?
    end

    # 6. Recreate group_groups edges using the mapping
    GroupGroup.where(parent_group_id: reachable_group_ids).each do |gg|
      next unless group_map[gg.parent_group_id] && group_map[gg.child_group_id]
      GroupGroup.create!(
        parent_group: group_map[gg.parent_group_id],
        child_group: group_map[gg.child_group_id]
      )
    end

    # 7. Recreate group_profiles using the mapping
    GroupProfile.where(group_id: reachable_group_ids).each do |gp|
      next unless group_map[gp.group_id] && profile_map[gp.profile_id]
      GroupProfile.create!(
        group: group_map[gp.group_id],
        profile: profile_map[gp.profile_id]
      )
    end

    # 8. Recreate inclusion overrides, remapping group IDs in paths
    InclusionOverride.where(group_id: reachable_group_ids).each do |override|
      new_root = group_map[override.group_id]
      next unless new_root

      new_path = override.path.map { |gid| group_map[gid]&.id }.compact
      next if new_path.length != override.path.length  # skip if mapping incomplete

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

### Controller

```ruby
def duplicate
  @source = Current.user.groups.find_by!(uuid: params[:id])
  if request.post?
    new_labels = params[:labels_text].to_s.split(",").map(&:strip).reject(&:blank?).uniq
    @group = @source.deep_duplicate(new_labels: new_labels)
    redirect_to our_group_path(@group), notice: "Group duplicated with all sub-groups and profiles."
  end
end
```

### View — `app/views/our/groups/duplicate.html.haml`

```haml
- content_for(:title) { "Duplicate #{@source.name} — Plural Profiles" }

%h1 Duplicate group

.card
  %p
    You are duplicating
    %strong= @source.name
    and its entire tree of sub-groups and profiles. Every item in the tree will be copied with a new share URL.

  = form_with url: duplicate_our_group_path(@source), method: :post do |form|
    .form-group
      = form.label :labels_text, "Labels for all copies (private, comma-separated)"
      = form.text_field :labels_text, value: params[:labels_text], placeholder: "e.g. work, public"
      %p.form-hint These labels will be applied to every copied group and profile. Leave blank for no labels.

    .form-group
      = form.submit "Create duplicate"
      = link_to "Cancel", our_group_path(@source), class: "btn btn--secondary"

%p= link_to "← Back to group", our_group_path(@source)
```

### Button on show page

Add a "Duplicate" button to group actions in `app/views/our/groups/show.html.haml`:

```haml
= link_to "Duplicate", duplicate_our_group_path(@group), class: "btn btn--secondary"
```

### Tests

- Model test: `deep_duplicate` creates correct number of groups, profiles, edges, and overrides.
- Model test: profiles appearing in multiple sub-groups are copied once and linked to all.
- Model test: inclusion overrides have correctly remapped paths and target IDs.
- Model test: all new records have new UUIDs and the specified labels.
- Controller test: POST duplicate creates the tree and redirects.
- System test: end-to-end duplicate flow.

---

## Phase summary

| Phase | What                                    | Key files changed                                                                |
| ----- | --------------------------------------- | -------------------------------------------------------------------------------- |
| 1     | Labels data layer (migration + concern) | migration, `HasLabels` concern, `Profile`, `Group`                               |
| 2     | Labels in profile forms and views       | `our/profiles/_form`, `our/profiles/show`, `our/profiles/index`, controller, CSS |
| 3     | Labels in group forms and views         | `our/groups/_form`, `our/groups/show`, `our/groups/index`, controller, CSS       |
| 4     | Filtering by label on index pages       | Both index views, both controllers, CSS                                          |
| 5     | Duplicate a profile                     | Route, controller, view, show page button                                        |
| 6     | Duplicate a group (deep copy)           | Route, controller, model method, view, show page button                          |

Each phase is independently shippable and testable. Phases 1–3 are prerequisites for everything. Phase 4 can be done anytime after 3. Phases 5 and 6 can be done independently of each other but both require Phase 1.
