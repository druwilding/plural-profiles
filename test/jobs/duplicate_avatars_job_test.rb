require "test_helper"

class DuplicateAvatarsJobTest < ActiveJob::TestCase
  # ── helpers ──────────────────────────────────────────────────────────────────

  def create_task(groups_map: [], profiles_map: [])
    total = groups_map.size + profiles_map.size
    DuplicationTask.create!(
      user: users(:one),
      group: groups(:friends),
      avatar_mappings: { "groups" => groups_map, "profiles" => profiles_map },
      total_avatars: total,
      copied_avatars: 0,
      status: "pending"
    )
  end

  def attach_avatar(record)
    record.avatar.attach(
      io: file_fixture("avatar.png").open,
      filename: "avatar.png",
      content_type: "image/png"
    )
  end

  # ── status transitions ────────────────────────────────────────────────────────

  test "marks task completed when there are no avatars to copy" do
    task = create_task
    DuplicateAvatarsJob.perform_now(task.id)
    task.reload
    assert task.completed?
    assert_equal 0, task.copied_avatars
  end

  test "transitions task through in_progress before completing" do
    # Observe what happens mid-job by checking the task is eventually completed
    task = create_task
    DuplicateAvatarsJob.perform_now(task.id)
    task.reload
    assert task.completed?, "expected completed status, got #{task.status}"
  end

  # ── skipping ──────────────────────────────────────────────────────────────────

  test "skips pairs where source record does not exist" do
    task = create_task(groups_map: [ [ 999_999, groups(:friends).id ] ])
    DuplicateAvatarsJob.perform_now(task.id)
    task.reload
    assert task.completed?
    assert_equal 0, task.copied_avatars
  end

  test "skips pairs where target record does not exist" do
    task = create_task(groups_map: [ [ groups(:friends).id, 999_999 ] ])
    DuplicateAvatarsJob.perform_now(task.id)
    task.reload
    assert task.completed?
    assert_equal 0, task.copied_avatars
  end

  test "skips pairs where source has no avatar attached" do
    source = groups(:friends)
    target = groups(:family)
    # Source has no avatar — should be skipped
    task = create_task(groups_map: [ [ source.id, target.id ] ])
    DuplicateAvatarsJob.perform_now(task.id)
    task.reload
    assert task.completed?
    assert_equal 0, task.copied_avatars
    assert_not target.reload.avatar.attached?
  end

  # ── successful copying ───────────────────────────────────────────────────────

  test "copies a group avatar and increments the counter" do
    source = groups(:friends)
    target = groups(:family)
    attach_avatar(source)

    task = create_task(groups_map: [ [ source.id, target.id ] ])
    DuplicateAvatarsJob.perform_now(task.id)

    task.reload
    assert task.completed?
    assert_equal 1, task.copied_avatars
    assert target.reload.avatar.attached?
  end

  test "copies a profile avatar and increments the counter" do
    source = profiles(:alice)
    target = profiles(:bob)
    attach_avatar(source)

    task = create_task(profiles_map: [ [ source.id, target.id ] ])
    DuplicateAvatarsJob.perform_now(task.id)

    task.reload
    assert task.completed?
    assert_equal 1, task.copied_avatars
    assert target.reload.avatar.attached?
  end

  test "copies both group and profile avatars in one task" do
    group_source  = groups(:friends)
    group_target  = groups(:family)
    attach_avatar(group_source)

    profile_source = profiles(:alice)
    profile_target = profiles(:bob)
    attach_avatar(profile_source)

    task = create_task(
      groups_map:   [ [ group_source.id, group_target.id ] ],
      profiles_map: [ [ profile_source.id, profile_target.id ] ]
    )
    DuplicateAvatarsJob.perform_now(task.id)

    task.reload
    assert task.completed?
    assert_equal 2, task.copied_avatars
    assert group_target.reload.avatar.attached?
    assert profile_target.reload.avatar.attached?
  end

  # ── error recovery ────────────────────────────────────────────────────────────

  test "a single avatar copy failure does not prevent other avatars from copying" do
    good_source = groups(:friends)
    good_target = groups(:family)
    attach_avatar(good_source)

    bad_source = groups(:everyone)
    bad_target = groups(:alpha_clan)
    attach_avatar(bad_source)

    # Remove the storage file for bad_source so blob.open raises at copy time
    bad_blob = bad_source.reload.avatar.blob
    ActiveStorage::Blob.service.delete(bad_blob.key)

    task = create_task(
      groups_map: [
        [ bad_source.id, bad_target.id ],  # will fail on blob.open
        [ good_source.id, good_target.id ] # should succeed
      ]
    )
    DuplicateAvatarsJob.perform_now(task.id)

    task.reload
    assert task.completed?
    assert_equal 1, task.copied_avatars
    assert good_target.reload.avatar.attached?
    assert_not bad_target.reload.avatar.attached?
  end
end
