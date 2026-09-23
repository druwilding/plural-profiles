require "test_helper"

class Emotes::RewriteProfileCodesJobTest < ActiveJob::TestCase
  setup do
    @alice = profiles(:alice)
    @alice.update_columns(heart_emojis: %w[dewdrop_heart cadbury_heart red_heart], mini_profile_heart_emojis: %w[cadbury_heart])
  end

  test "replaces the old code in place, keeping the order" do
    Emotes::RewriteProfileCodesJob.perform_now("cadbury_heart", "chocolate_heart")

    @alice.reload
    assert_equal %w[dewdrop_heart chocolate_heart red_heart], @alice.heart_emojis
    assert_equal %w[chocolate_heart], @alice.mini_profile_heart_emojis
  end

  test "removes the old code when there's no new one" do
    Emotes::RewriteProfileCodesJob.perform_now("cadbury_heart", nil)

    @alice.reload
    assert_equal %w[dewdrop_heart red_heart], @alice.heart_emojis
    assert_equal [], @alice.mini_profile_heart_emojis
  end

  test "leaves profiles without the code alone" do
    bob = profiles(:bob)
    bob.update_columns(heart_emojis: %w[aqua_heart])

    Emotes::RewriteProfileCodesJob.perform_now("cadbury_heart", "chocolate_heart")

    assert_equal %w[aqua_heart], bob.reload.heart_emojis
  end
end
