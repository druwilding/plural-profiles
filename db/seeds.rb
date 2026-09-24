# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# The original hearts, as the site-wide "Hearts" emote group, for a fresh
# database: db:setup and db:prepare load the schema rather than running
# migrations, so ImportHeartsAsEmotes never runs there. Skipped while any
# emotes exist, so it doesn't bring back hearts an admin has deleted. (If every
# emote is deleted, seeding imports the hearts again; deploys only migrate, so
# that only happens if someone runs db:seed by hand.)
if Emote.none?
  hearts = EmoteGroup.site_wide.find_or_create_by!(name: "Hearts") { |group| group.position = 0 }

  Dir[Rails.root.join("db/emotes/hearts/*.webp")].sort.each do |path|
    name = File.basename(path, ".webp")
    emote = hearts.emotes.new(name: name)
    emote.image.attach(io: File.open(path), filename: "#{Emote.default_code(name)}.webp", content_type: "image/webp")
    emote.save!
  end
end
