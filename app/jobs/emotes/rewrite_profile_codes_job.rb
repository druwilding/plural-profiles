# Rewrites an emote code stored in profiles' picked emotes (heart_emojis and
# mini_profile_heart_emojis) after an admin renames or deletes the emote.
#
# With a new code, the old one is replaced in place, keeping the order. With
# nil (the emote was deleted), the old code is removed.
#
# Only tidies stored data: reads already resolve old codes through aliases.
class Emotes::RewriteProfileCodesJob < ApplicationJob
  COLUMNS = %w[heart_emojis mini_profile_heart_emojis].freeze

  def perform(old_code, new_code)
    COLUMNS.each do |column|
      Profile.where("#{column} @> jsonb_build_array(?::text)", old_code)
        .update_all([ rewritten_sql(column, new_code), { old: old_code, new: new_code } ])
    end
  end

  private

  def rewritten_sql(column, new_code)
    element = new_code.nil? ? "value" : "CASE WHEN value = to_jsonb(:old::text) THEN to_jsonb(:new::text) ELSE value END"
    filter = new_code.nil? ? "WHERE value <> to_jsonb(:old::text)" : ""

    <<~SQL.squish
      #{column} = COALESCE((
        SELECT jsonb_agg(#{element} ORDER BY position)
        FROM jsonb_array_elements(#{column}) WITH ORDINALITY AS elements(value, position)
        #{filter}
      ), '[]'::jsonb)
    SQL
  end
end
