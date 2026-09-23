require "test_helper"

class InclusionOverrideTest < ActiveSupport::TestCase
  setup do
    @user = users(:three)
    @alpha = groups(:alpha_clan)
  end

  test "valid override is saved" do
    override = InclusionOverride.new(
      group: @alpha,
      path: [],
      target_type: "Group",
      target_id: groups(:spectrum).id
    )
    assert override.valid?
  end

  test "requires target_type to be Group or Profile" do
    override = InclusionOverride.new(
      group: @alpha,
      path: [],
      target_type: "User",
      target_id: @user.id
    )
    assert_not override.valid?
    assert_includes override.errors[:target_type], "is not included in the list"
  end

  test "uniqueness enforced at database level for group_id, path, target_type, target_id" do
    # The fixture already has rogue_pack_hidden_in_alpha_via_spectrum.
    # JSONB equality isn't handled by Rails' uniqueness validator, but the
    # database unique index enforces it.
    existing = inclusion_overrides(:rogue_pack_hidden_in_alpha_via_spectrum)
    duplicate = InclusionOverride.new(
      group_id: existing.group_id,
      path: existing.path,
      target_type: existing.target_type,
      target_id: existing.target_id
    )
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  test "same target at different paths is allowed" do
    # Rogue Pack is already hidden at path [spectrum, prism_circle]
    # Hiding it at a different path should work
    override = InclusionOverride.new(
      group: @alpha,
      path: [ groups(:echo_shard).id, groups(:prism_circle).id ],
      target_type: "Group",
      target_id: groups(:rogue_pack).id
    )
    assert override.valid?
  end

  test "nil path is normalised to empty array" do
    # The normalise_path callback converts nil → [] before validation,
    # so nil path is accepted and stored as an empty array.
    override = InclusionOverride.new(
      group: @alpha,
      target_type: "Group",
      target_id: groups(:spectrum).id
    )
    override.path = nil
    assert override.valid?, "Override with nil path should be valid (normalised to []):\n#{override.errors.full_messages}"
    assert_equal [], override.path
  end

  test "empty path works for root-level items" do
    override = InclusionOverride.new(
      group: @alpha,
      path: [],
      target_type: "Profile",
      target_id: profiles(:grove).id
    )
    assert override.valid?
  end

  test "same_user validation rejects cross-user target" do
    # Alpha Clan belongs to user three. Alice belongs to user one.
    override = InclusionOverride.new(
      group: @alpha,
      path: [],
      target_type: "Profile",
      target_id: profiles(:alice).id
    )
    assert_not override.valid?
    assert_includes override.errors[:target], "must belong to the same user"
  end

  test "path_groups_exist validation rejects unreachable group in path" do
    override = InclusionOverride.new(
      group: @alpha,
      path: [ 999_999_999 ],
      target_type: "Group",
      target_id: groups(:spectrum).id
    )
    assert_not override.valid?
    assert_includes override.errors[:path], "contains a group not in this tree"
  end

  test "path normalisation converts strings to integers" do
    override = InclusionOverride.new(
      group: @alpha,
      path: [ groups(:spectrum).id.to_s ],
      target_type: "Group",
      target_id: groups(:prism_circle).id
    )
    override.valid?
    assert_equal [ groups(:spectrum).id ], override.path
  end

  test "cascade delete when root group is destroyed" do
    count = InclusionOverride.where(group_id: @alpha.id).count
    assert count > 0, "Precondition: alpha should have overrides"

    assert_difference("InclusionOverride.count", -count) do
      @alpha.destroy
    end
  end

  test "fixture overrides are valid" do
    inclusion_overrides(:rogue_pack_hidden_in_alpha_via_spectrum).tap do |o|
      assert o.valid?, "Fixture override should be valid: #{o.errors.full_messages}"
      assert_equal "Group", o.target_type
      assert_equal groups(:rogue_pack).id, o.target_id
    end

    inclusion_overrides(:drift_hidden_in_castle).tap do |o|
      assert o.valid?, "Fixture override should be valid: #{o.errors.full_messages}"
      assert_equal "Profile", o.target_type
      assert_equal profiles(:drift).id, o.target_id
    end
  end

  # -- prune_stale! ---

  test "prune_stale! keeps overrides whose route still exists" do
    assert_no_difference("InclusionOverride.count") do
      InclusionOverride.prune_stale!(@user)
    end
  end

  test "prune_stale! removes overrides routed through a removed group link" do
    group_groups(:prism_in_spectrum).destroy
    InclusionOverride.prune_stale!(@user)
    assert_not InclusionOverride.exists?(ActiveRecord::FixtureSet.identify(:rogue_pack_hidden_in_alpha_via_spectrum))
  end

  test "prune_stale! removes overrides whose target profile left the group" do
    group_profiles(:drift_in_flux).destroy
    InclusionOverride.prune_stale!(@user)
    assert_not InclusionOverride.exists?(ActiveRecord::FixtureSet.identify(:drift_hidden_in_castle))
    assert InclusionOverride.exists?(ActiveRecord::FixtureSet.identify(:ripple_hidden_in_castle))
  end

  test "prune_stale! removes overrides whose target group left the parent" do
    group_groups(:static_in_flux).destroy
    InclusionOverride.prune_stale!(@user)
    assert_not InclusionOverride.exists?(ActiveRecord::FixtureSet.identify(:static_burst_hidden_in_castle))
  end

  test "prune_stale! only touches the given user's overrides" do
    group_profiles(:drift_in_flux).delete
    InclusionOverride.prune_stale!(users(:one))
    assert InclusionOverride.exists?(ActiveRecord::FixtureSet.identify(:drift_hidden_in_castle))
  end

  test "unticking a parent group on a group prunes overrides through that link" do
    groups(:flux).update!(selected_parent_group_ids: [ "" ])
    assert_not InclusionOverride.exists?(ActiveRecord::FixtureSet.identify(:drift_hidden_in_castle))
  end

  test "removing a group from a profile prunes overrides for that profile" do
    profiles(:drift).update!(group_ids: [ "" ])
    assert_not InclusionOverride.exists?(ActiveRecord::FixtureSet.identify(:drift_hidden_in_castle))
  end

  test "deleting a group prunes overrides routed through it in other trees" do
    groups(:flux).destroy
    assert_not InclusionOverride.exists?(ActiveRecord::FixtureSet.identify(:drift_hidden_in_castle))
  end

  test "re-adding a removed link does not bring old overrides back" do
    flux = groups(:flux)
    flux.update!(selected_parent_group_ids: [ "" ])
    flux.update!(selected_parent_group_ids: [ groups(:castle_clan).id ])
    assert_not InclusionOverride.exists?(ActiveRecord::FixtureSet.identify(:drift_hidden_in_castle))
  end
end
