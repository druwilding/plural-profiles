# Moves the hardcoded hearts (formerly HeartEmoji::ALL) into the database, as
# a "Hearts" emote group. The images are in db/emotes/hearts, named after each
# heart's emote (e.g. 01_dewdrop_heart.webp); db/seeds.rb imports the same
# folder into a fresh database, which loads the schema without running this.
#
# Each heart's code stays exactly as before (e.g. "dewdrop_heart"), so every
# heart code already written in text or picked on a profile keeps resolving.
# Names get a number prefix in the old display order ("01_dewdrop_heart"), the
# naming convention admins use to order emotes.
#
# This runs as a migration rather than a rake task so it happens exactly once
# per environment: re-running an import on every deploy would bring back
# hearts an admin had since deleted.
class ImportHeartsAsEmotes < ActiveRecord::Migration[8.1]
  HEARTS = %w[
    dewdrop_heart spring_heart hunter_heart woods_heart seafoam_heart
    fern_heart moss_heart bramble_heart wild_heart aqua_heart
    ocean_heart storm_heart abyss_heart frozen_heart ice_heart
    cornflower_heart azure_heart nightsky_heart haunted_heart mist_heart
    lavender_heart violet_heart aubegine_heart shadow_heart inky_heart
    blossom_heart burgundy_heart arcane_heart void_heart vulnerable_heart
    filthy_heart passionate_heart blackened_heart hungry_heart princess_heart
    red_heart murder_heart dawn_heart peach_heart tangerine_heart
    bone_heart fawn_heart fur_heart soil_heart sunlit_heart
    lemondrop_heart nox_heart cadbury_heart maroon_heart sunshine_heart
  ].freeze

  GROUP_NAME = "Hearts".freeze

  def up
    [ EmoteGroup, Emote, EmoteAlias ].each(&:reset_column_information)

    group = EmoteGroup.site_wide.find_or_create_by!(name: GROUP_NAME) do |new_group|
      new_group.position = 0
      new_group.plain_text = "♥"
    end

    HEARTS.each.with_index(1) do |heart, number|
      next if Emote.exists?(code: heart) || EmoteAlias.exists?(code: heart)

      name = format("%02d_%s", number, heart)
      raise "expected #{name} to derive the code #{heart}" unless Emote.default_code(name) == heart

      emote = group.emotes.new(name: name)
      emote.image.attach(
        io: File.open(Rails.root.join("db/emotes/hearts/#{name}.webp")),
        filename: "#{heart}.webp",
        content_type: "image/webp"
      )
      emote.save!
    end
  end

  def down
    group = EmoteGroup.site_wide.find_by(name: GROUP_NAME)
    return unless group

    group.emotes.where(code: HEARTS).find_each do |emote|
      emote.image.purge
      emote.destroy!
    end
    group.destroy! if group.emotes.reload.none?
  end
end
