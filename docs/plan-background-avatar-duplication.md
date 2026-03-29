# Plan: Background Avatar Duplication

## Summary

When duplicating a group tree, avatar copying currently happens synchronously during the HTTP request. Each avatar requires downloading the blob from S3 to a tempfile and re-uploading it — on S3, this takes a few seconds per avatar. For a large tree with many groups and profiles, this can make the request unacceptably slow.

Move avatar copying to a background job. After the data duplication (groups, profiles, edges, overrides) completes synchronously, enqueue a single `DuplicateAvatarsJob` and redirect the user to a progress page that shows a live counter ("Copied 3 of 12 avatars…"). Once complete, the progress page redirects to the new group.

### Key decisions from discussion

- **Keep `:async` Active Job adapter** — no new infrastructure; the job runs in Puma worker threads, same process. Good enough given the app's scale and Scalingo hosting.
- **One job per duplication** — a single `DuplicateAvatarsJob` receives a task ID and copies all avatars in sequence. Simpler than one-job-per-avatar.
- **Progress page with counter** — after clicking "Duplicate", the user lands on a progress page that polls for status and shows "Copied N of M avatars…". On completion, it redirects to the new group.
- **Poll via Stimulus controller** — a small Stimulus `progress-poll` controller fetches a JSON status endpoint every 2 seconds and updates the counter. On completion, triggers a `Turbo.visit` to the new group.
- **Retry then give up on failure** — the job retries transient errors (S3 timeouts) up to 3 times, then marks the remaining avatars as failed and completes. No user notification; failed copies simply have no avatar (the existing placeholder UI handles this gracefully).

---

## Current state

Avatar copying lives in `Group#deep_duplicate` ([app/models/group.rb](app/models/group.rb)), after the main transaction:

```ruby
# Copy avatars after the transaction so Active Storage's after_create_commit
# callback can read the IO without hitting a closed stream.
group_map.each do |old_id, new_group|
  next if reused_group_ids.include?(old_id) || skip_ids.include?(old_id)
  original = groups_by_id[old_id]
  duplicate_avatar(original, new_group) if original&.avatar&.attached?
end

profile_map.each do |old_id, new_profile|
  next if reused_profile_ids.include?(old_id)
  original = profiles_by_id[old_id]
  duplicate_avatar(original, new_profile) if original&.avatar&.attached?
end
```

Each `duplicate_avatar` call does `blob.open` (downloads to tempfile) → `target.avatar.attach` (re-uploads). On S3, each round-trip takes 1–5 seconds depending on file size and network conditions. A tree with 20 avatars could easily take 30–60 seconds — too long for a web request.

The production queue adapter is `:async` (in-process threads, no separate worker). There are no existing custom job classes.

---

## Phase 1: DuplicationTask model

Track job progress in the database so the progress page can query it.

### Migration

```ruby
class CreateDuplicationTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :duplication_tasks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :group, null: false, foreign_key: true
      t.jsonb :avatar_mappings, null: false, default: {}
      t.integer :total_avatars, null: false, default: 0
      t.integer :copied_avatars, null: false, default: 0
      t.string :status, null: false, default: "pending"
      t.timestamps
    end
  end
end
```

### Model

Create `app/models/duplication_task.rb`:

```ruby
class DuplicationTask < ApplicationRecord
  belongs_to :user
  belongs_to :group

  STATUSES = %w[pending in_progress completed failed].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: %w[pending in_progress]) }

  def completed? = status == "completed"
  def failed? = status == "failed"
  def in_progress? = status == "in_progress"
  def pending? = status == "pending"
  def finished? = completed? || failed?

  def progress_text
    "Copied #{copied_avatars} of #{total_avatars} avatars"
  end
end
```

The `avatar_mappings` jsonb column stores the work to be done:

```json
{
  "groups": [[source_id, target_id], [source_id, target_id], ...],
  "profiles": [[source_id, target_id], [source_id, target_id], ...]
}
```

This keeps the job self-contained — it only needs the task ID.

### User association

Add to `User`:

```ruby
has_many :duplication_tasks, dependent: :destroy
```

### Tests

- Unit tests for status predicates and `progress_text`.
- Validate that `avatar_mappings` round-trips correctly.

---

## Phase 2: DuplicateAvatarsJob

Create `app/jobs/duplicate_avatars_job.rb`:

```ruby
class DuplicateAvatarsJob < ApplicationJob
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(duplication_task_id)
    task = DuplicationTask.find(duplication_task_id)
    task.update!(status: "in_progress")

    mappings = task.avatar_mappings

    copy_avatars(mappings["groups"], Group, task)
    copy_avatars(mappings["profiles"], Profile, task)

    task.update!(status: "completed")
  rescue StandardError => e
    task&.update(status: "failed") if task&.persisted?
    raise # Re-raise so Active Job's retry_on can handle it
  end

  private

  def copy_avatars(pairs, klass, task)
    return if pairs.blank?

    pairs.each do |source_id, target_id|
      source = klass.find_by(id: source_id)
      target = klass.find_by(id: target_id)
      next unless source && target && source.avatar.attached?

      begin
        source.avatar.blob.open do |tempfile|
          target.avatar.attach(
            io: tempfile,
            filename: source.avatar.blob.filename,
            content_type: source.avatar.blob.content_type
          )
        end
      rescue => e
        Rails.logger.warn "[DuplicateAvatarsJob] Failed to copy avatar " \
          "#{klass.name}##{source_id} → ##{target_id}: #{e.message}"
        next # Skip this avatar, continue with the rest
      end

      task.increment!(:copied_avatars)
    end
  end
end
```

### Retry strategy

`retry_on StandardError` with 3 attempts covers transient S3 errors. The `rescue` inside `copy_avatars` handles individual avatar failures gracefully — it logs and continues, so one bad blob doesn't block the rest.

Note: `retry_on` at the job level handles the case where the entire job fails (e.g. DB connection lost). Individual avatar copy failures are caught and skipped within the loop, so they don't trigger a full job retry.

### Tests

- Test that the job copies avatars and increments the counter.
- Test that the job marks the task `completed` when done.
- Test that a single avatar failure doesn't prevent others from copying.
- Test that the job marks the task `failed` on total failure.

---

## Phase 3: Update `deep_duplicate` to skip avatars

Modify `Group#deep_duplicate` to **return the avatar mapping data** instead of copying avatars inline.

### Changes to `deep_duplicate`

Replace the avatar-copying loops at the end of `deep_duplicate` with code that builds and returns the mapping:

```ruby
# Build avatar mapping for background job instead of copying inline.
avatar_mappings = { "groups" => [], "profiles" => [] }

group_map.each do |old_id, new_group|
  next if reused_group_ids.include?(old_id) || skip_ids.include?(old_id)
  original = groups_by_id[old_id]
  if original&.avatar&.attached?
    avatar_mappings["groups"] << [original.id, new_group.id]
  end
end

profile_map.each do |old_id, new_profile|
  next if reused_profile_ids.include?(old_id)
  original = profiles_by_id[old_id]
  if original&.avatar&.attached?
    avatar_mappings["profiles"] << [original.id, new_profile.id]
  end
end

{ group: group_map[id], avatar_mappings: avatar_mappings }
```

The return value changes from a single `Group` to a hash with the new root group and the mapping data. The controller will use both.

### Tests

- Existing duplication tests should be updated to expect the new return shape.
- Verify that avatars are **not** copied during `deep_duplicate` (the new group/profile records should exist but have no avatars attached).

---

## Phase 4: Controller changes

### `duplicate_execute`

Update to create a `DuplicationTask`, enqueue the job, and redirect to the progress page:

```ruby
def duplicate_execute
  wizard = session[:duplication_wizard]
  unless wizard
    redirect_to our_group_path(@group), alert: "No duplication in progress."
    return
  end

  labels = wizard["labels"]
  resolutions = wizard["resolutions"] || {}
  profile_resolutions = wizard["profile_resolutions"] || {}

  result = @group.deep_duplicate(
    new_labels: labels, resolutions: resolutions, profile_resolutions: profile_resolutions
  )

  new_group = result[:group]
  avatar_mappings = result[:avatar_mappings]
  total = avatar_mappings["groups"].size + avatar_mappings["profiles"].size

  if total > 0
    task = current_user.duplication_tasks.create!(
      group: new_group,
      avatar_mappings: avatar_mappings,
      total_avatars: total,
      status: "pending"
    )
    DuplicateAvatarsJob.perform_later(task.id)
    session.delete(:duplication_wizard)
    redirect_to duplicate_progress_our_group_path(new_group, task_id: task.id)
  else
    # No avatars to copy — skip the progress page entirely.
    session.delete(:duplication_wizard)
    redirect_to our_group_path(new_group),
                notice: "Group duplicated with all sub-groups and profiles."
  end
end
```

When there are no avatars, the user goes straight to the new group — no unnecessary progress page.

### New action: `duplicate_progress`

```ruby
def duplicate_progress
  @task = current_user.duplication_tasks.find(params[:task_id])
  @group = @task.group

  if @task.finished?
    redirect_to our_group_path(@group),
                notice: "Group duplicated with all sub-groups and profiles."
  end
  # Otherwise renders the progress page
end
```

### New action: `duplicate_status` (JSON)

```ruby
def duplicate_status
  task = current_user.duplication_tasks.find(params[:task_id])
  render json: {
    status: task.status,
    copied: task.copied_avatars,
    total: task.total_avatars,
    redirect_url: task.finished? ? our_group_path(task.group) : nil
  }
end
```

### Routes

Add under the group member routes (alongside existing duplication actions):

```ruby
get  :duplicate_progress
get  :duplicate_status
```

### Tests

- Controller test: `duplicate_execute` with avatars creates a task and enqueues a job.
- Controller test: `duplicate_execute` without avatars redirects directly.
- Controller test: `duplicate_progress` renders when task is in progress.
- Controller test: `duplicate_progress` redirects when task is finished.
- Controller test: `duplicate_status` returns JSON with correct shape.

---

## Phase 5: Progress page view & Stimulus controller

### View: `app/views/our/groups/duplicate_progress.html.haml`

```haml
.pane
  .pane__header
    %h1 Duplicating group…

  .pane__body
    .duplication-progress{ data: { controller: "progress-poll",
                                    "progress-poll-url-value" => duplicate_status_our_group_path(@group, task_id: @task.id),
                                    "progress-poll-redirect-notice-value" => "Group duplicated with all sub-groups and profiles." } }
      %p.duplication-progress__message
        Copying avatars…
      .duplication-progress__counter{ data: { "progress-poll-target" => "counter" } }
        Copied #{@task.copied_avatars} of #{@task.total_avatars} avatars
      .duplication-progress__spinner
```

### Stimulus controller: `app/javascript/controllers/progress_poll_controller.js`

```javascript
import { Controller } from "@hotwired/stimulus"
import { visit } from "@hotwired/turbo"

export default class extends Controller {
  static targets = ["counter"]
  static values = {
    url: String,
    interval: { type: Number, default: 2000 },
    redirectNotice: { type: String, default: "" }
  }

  connect() {
    this.poll()
    this.timer = setInterval(() => this.poll(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async poll() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { "Accept": "application/json" }
      })
      if (!response.ok) return

      const data = await response.json()
      this.counterTarget.textContent = `Copied ${data.copied} of ${data.total} avatars`

      if (data.redirect_url) {
        clearInterval(this.timer)
        // Use Turbo visit so the flash notice works with Turbo Drive
        visit(data.redirect_url)
      }
    } catch {
      // Silently ignore fetch errors — will retry on next interval
    }
  }
}
```

Register in `app/javascript/controllers/index.js` (or via automatic Stimulus loading if using `eagerLoadControllersFrom`).

### CSS

Add styles for `.duplication-progress` in `application.css`:

```css
.duplication-progress {
  text-align: center;
  padding: 2rem 1rem;
}

.duplication-progress__counter {
  font-size: 1.25rem;
  font-weight: 600;
  color: var(--heading);
  margin: 1rem 0;
}

.duplication-progress__spinner {
  width: 2rem;
  height: 2rem;
  margin: 1rem auto;
  border: 3px solid var(--pane-border);
  border-top-color: var(--primary-button-bg);
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

@media (forced-colors: active) {
  .duplication-progress__spinner {
    border-color: ButtonFace;
    border-top-color: Highlight;
  }
}
```

### Tests

- System test: duplicating a group with avatars shows the progress page, then redirects to the new group once complete.

---

## Phase 6: Cleanup old tasks

Old `DuplicationTask` records are no longer useful once the job finishes. Add a simple cleanup mechanism.

### Option A: TTL-based deletion in a recurring task

If recurring tasks are ever enabled (Solid Queue), add a daily job to delete tasks older than 7 days.

### Option B: Eager cleanup

Delete the task record when the progress page successfully redirects:

```ruby
def duplicate_progress
  @task = current_user.duplication_tasks.find(params[:task_id])
  @group = @task.group

  if @task.finished?
    @task.destroy
    redirect_to our_group_path(@group),
                notice: "Group duplicated with all sub-groups and profiles."
  end
end
```

This is simpler and avoids accumulating rows. **Recommended.**

---

## Edge cases

### User navigates away from progress page
The job keeps running. Avatars will appear as they're copied. The progress page URL remains valid (task still exists) if they come back. Once the task finishes and they visit the progress page, it redirects to the new group.

### User closes browser entirely
Same as above — the job is in-process and keeps running. Next time they visit the new group, any avatars that were copied will be there; any that weren't will show the placeholder.

### Process restart during job execution
With the `:async` adapter, the job is lost on restart. The `DuplicationTask` will remain in `pending` or `in_progress` status permanently. The new group will exist (data duplication was synchronous) but some avatars will be missing — the user sees placeholders and can re-upload manually.

This is an accepted trade-off of the `:async` adapter. If it becomes a problem, migrating to Solid Queue (database-backed, survives restarts) is a future option, and this plan's architecture would support it with no changes other than swapping the adapter.

### No avatars in the tree
The controller skips the progress page entirely and redirects straight to the new group with the success notice.

### Avatar source deleted during job
The `find_by` in the job returns `nil`, and the pair is skipped. The counter still increments for successful copies. The total may not match the copied count, but the job completes normally.

---

## Migration path to Solid Queue (future)

If the `:async` adapter's lack of persistence becomes a concern:

1. Add `solid_queue` to the Gemfile.
2. Run the Solid Queue install generator to create the queue database tables.
3. Set `config.active_job.queue_adapter = :solid_queue` in production.
4. Enable the Puma plugin: `SOLID_QUEUE_IN_PUMA=1` env var (already wired in `config/puma.rb`).
5. No changes to the job, task model, or controllers — they all work through Active Job's standard interface.

---

## File summary

| File                                                     | Action                                                                   |
| -------------------------------------------------------- | ------------------------------------------------------------------------ |
| `db/migrate/xxx_create_duplication_tasks.rb`             | New migration                                                            |
| `app/models/duplication_task.rb`                         | New model                                                                |
| `app/models/user.rb`                                     | Add `has_many :duplication_tasks`                                        |
| `app/models/group.rb`                                    | Change `deep_duplicate` return value; remove inline avatar copying       |
| `app/jobs/duplicate_avatars_job.rb`                      | New job                                                                  |
| `app/controllers/our/groups_controller.rb`               | Update `duplicate_execute`; add `duplicate_progress`, `duplicate_status` |
| `config/routes.rb`                                       | Add `duplicate_progress`, `duplicate_status` routes                      |
| `app/views/our/groups/duplicate_progress.html.haml`      | New progress page view                                                   |
| `app/javascript/controllers/progress_poll_controller.js` | New Stimulus controller                                                  |
| `app/assets/stylesheets/application.css`                 | Progress page styles                                                     |
| `test/models/duplication_task_test.rb`                   | New model tests                                                          |
| `test/jobs/duplicate_avatars_job_test.rb`                | New job tests                                                            |
| `test/controllers/our/groups_controller_test.rb`         | Updated/new controller tests                                             |
| `test/system/duplication_test.rb` (or similar)           | Updated system tests                                                     |
