# Moves the hardcoded hearts (formerly HeartEmoji::ALL) into the database, as
# a "Hearts" emote group. The images are in db/emotes/hearts, named after each
# heart's emote (e.g. 01-dewdrop-heart.webp, since emote identifiers switched to
# hyphens in ConvertEmoteIdentifiersToHyphens); db/seeds.rb imports the same
# folder into a fresh database, which loads the schema without running this.
#
# Each heart's code stays exactly as before (e.g. "dewdrop_heart"), so every
# heart code already written in text or picked on a profile keeps resolving.
# Names get a number prefix in the old display order ("01_dewdrop_heart"), the
# naming convention admins use to order emotes. (Later migrations turn the
# underscores into hyphens and the groups into sets.)
#
# This runs as a migration rather than a rake task so it happens exactly once
# per environment: re-running an import on every deploy would bring back
# hearts an admin had since deleted.
#
# It uses its own models for the tables as they were at this point, so it
# still runs from an empty database after the app's models have moved on
# (EmoteGroup is now EmoteSet).
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

  class EmoteGroup < ActiveRecord::Base
    self.table_name = "emote_groups"
    has_many :emotes, class_name: "ImportHeartsAsEmotes::Emote", foreign_key: :emote_group_id
  end

  class Emote < ActiveRecord::Base
    self.table_name = "emotes"
    has_one_attached :image

    # Attachments are stored against the app's Emote, not this class.
    def self.polymorphic_name
      "Emote"
    end
  end

  class EmoteAlias < ActiveRecord::Base
    self.table_name = "emote_aliases"
  end

  def up
    [ EmoteGroup, Emote, EmoteAlias ].each(&:reset_column_information)

    group = EmoteGroup.find_or_create_by!(owner_type: nil, owner_id: nil, name: GROUP_NAME) do |new_group|
      new_group.position = 0
      new_group.plain_text = "♥"
    end

    HEARTS.each.with_index(1) do |heart, number|
      next if Emote.exists?(code: heart) || EmoteAlias.exists?(code: heart)

      name = format("%02d_%s", number, heart)
      emote = group.emotes.new(name: name, code: heart)
      emote.image.attach(
        io: File.open(Rails.root.join("db/emotes/hearts/#{name.tr("_", "-")}.webp")),
        filename: "#{heart}.webp",
        content_type: "image/webp"
      )
      emote.save!
    end
  end

  def down
    [ EmoteGroup, Emote, EmoteAlias ].each(&:reset_column_information)

    group = EmoteGroup.find_by(owner_type: nil, owner_id: nil, name: GROUP_NAME)
    return unless group

    group.emotes.where(code: HEARTS).find_each do |emote|
      emote.image.purge
      emote.destroy!
    end
    group.destroy! if group.emotes.reload.none?
  end
end
