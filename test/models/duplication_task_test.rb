require "test_helper"

class DuplicationTaskTest < ActiveSupport::TestCase
  # Status predicates

  test "pending? returns true for pending status" do
    assert duplication_tasks(:pending_task).pending?
  end

  test "in_progress? returns true for in_progress status" do
    assert duplication_tasks(:in_progress_task).in_progress?
  end

  test "completed? returns true for completed status" do
    assert duplication_tasks(:completed_task).completed?
  end

  test "failed? returns true for failed status" do
    assert duplication_tasks(:failed_task).failed?
  end

  test "finished? returns true for completed status" do
    assert duplication_tasks(:completed_task).finished?
  end

  test "finished? returns true for failed status" do
    assert duplication_tasks(:failed_task).finished?
  end

  test "finished? returns false for pending status" do
    assert_not duplication_tasks(:pending_task).finished?
  end

  test "finished? returns false for in_progress status" do
    assert_not duplication_tasks(:in_progress_task).finished?
  end

  # progress_text

  test "progress_text formats copied and total avatars" do
    task = duplication_tasks(:pending_task)
    assert_equal "Copied 0 of 2 avatars", task.progress_text
  end

  test "progress_text reflects completed count" do
    task = duplication_tasks(:completed_task)
    assert_equal "Copied 3 of 3 avatars", task.progress_text
  end

  # Validation

  test "rejects invalid status" do
    task = DuplicationTask.new(
      user: users(:one),
      group: groups(:friends),
      status: "bogus"
    )
    assert_not task.valid?
    assert_includes task.errors[:status], "is not included in the list"
  end

  test "requires user" do
    task = DuplicationTask.new(group: groups(:friends), status: "pending")
    assert_not task.valid?
    assert task.errors[:user].any?
  end

  test "requires group" do
    task = DuplicationTask.new(user: users(:one), status: "pending")
    assert_not task.valid?
    assert task.errors[:group].any?
  end

  # avatar_mappings round-trip

  test "avatar_mappings round-trips groups and profiles" do
    task = duplication_tasks(:pending_task)
    assert_equal 1, task.avatar_mappings["groups"].size
    assert_equal 1, task.avatar_mappings["profiles"].size
  end

  test "avatar_mappings defaults to empty hash on new record" do
    task = DuplicationTask.new
    assert_equal({}, task.avatar_mappings)
  end

  # Associations

  test "belongs to user" do
    assert_equal users(:one), duplication_tasks(:pending_task).user
  end

  test "belongs to group" do
    assert_equal groups(:friends), duplication_tasks(:pending_task).group
  end

  test "user has many duplication_tasks" do
    assert_includes users(:one).duplication_tasks, duplication_tasks(:pending_task)
  end

  # active scope

  test "active scope includes pending tasks" do
    assert_includes DuplicationTask.active, duplication_tasks(:pending_task)
  end

  test "active scope includes in_progress tasks" do
    assert_includes DuplicationTask.active, duplication_tasks(:in_progress_task)
  end

  test "active scope excludes completed tasks" do
    assert_not_includes DuplicationTask.active, duplication_tasks(:completed_task)
  end

  test "active scope excludes failed tasks" do
    assert_not_includes DuplicationTask.active, duplication_tasks(:failed_task)
  end
end
