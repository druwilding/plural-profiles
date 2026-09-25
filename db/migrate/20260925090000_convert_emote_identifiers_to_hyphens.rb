# Emote names, codes and old codes (aliases) are now stored with hyphens
# instead of underscores: "02_spring_heart" becomes "02-spring-heart" and
# :spring_heart: becomes :spring-heart:. Hyphens weren't allowed before, so no
# two identifiers can end up the same.
#
# Text already written with underscores (:spring_heart:) keeps working, because
# EmoteRegistry#resolve reads underscores as hyphens, so it isn't rewritten.
#
# updated_at is bumped so every process rebuilds its EmoteRegistry.
class ConvertEmoteIdentifiersToHyphens < ActiveRecord::Migration[8.1]
  def up
    convert("_", "-")
  end

  def down
    convert("-", "_")
  end

  private

  def convert(from, to)
    execute <<~SQL.squish
      UPDATE emotes SET
        name = replace(name, '#{from}', '#{to}'),
        code = replace(code, '#{from}', '#{to}'),
        updated_at = now()
    SQL
    execute <<~SQL.squish
      UPDATE emote_aliases SET
        code = replace(code, '#{from}', '#{to}'),
        updated_at = now()
    SQL
  end
end
