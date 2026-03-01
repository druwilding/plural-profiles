# Phase 1 seed script — deep inclusion test scenario
# Run with: bin/rails runner script/phase1_seed.rb
#
# Creates the full Phase 1 group/profile hierarchy under user id 1.
# Safe to re-run: wraps everything in a transaction and skips if alpha_clan already exists.

FIXTURE_FILES = Rails.root.join("test/fixtures/files")

def attach_avatar(record, path)
  record.avatar.attach(
    io: File.open(path),
    filename: File.basename(path),
    content_type: "image/png"
  )
end

email = ARGV.first
user = email ? User.find_by!(email_address: email) : User.find(1)
puts "Seeding for #{user.email_address} (id #{user.id})."

if user.groups.exists?(name: "Alpha Clan")
  puts "Alpha Clan already exists for #{user.email_address} — skipping. Delete it first if you want to re-seed."
  exit
end

ActiveRecord::Base.transaction do
  # ── Groups ────────────────────────────────────────────────────────────────

  alpha_clan   = user.groups.create!(name: "Alpha Clan",   description: "A clan at the top of the tree.")
  delta_clan   = user.groups.create!(name: "Delta Clan",   description: "Another clan.")
  spectrum     = user.groups.create!(name: "Spectrum",     description: "Overarching category spanning clans.")
  prism_circle = user.groups.create!(name: "Prism Circle", description: "Sub-category inside Spectrum.")
  rogue_pack   = user.groups.create!(name: "Rogue Pack",   description: "Sub-group of Prism Circle; its own independent clan.")
  flux         = user.groups.create!(name: "Flux",         description: "Category spanning multiple clans.")
  echo_shard   = user.groups.create!(name: "Echo Shard",   description: "Sub-group of Flux.")
  static_burst = user.groups.create!(name: "Static Burst", description: "Another sub-group of Flux.")
  delta_flux   = user.groups.create!(name: "Delta Flux",   description: "Flux section specific to Delta Clan.")

  [
    [ alpha_clan,   "alpha_clan" ],
    [ delta_clan,   "delta_clan" ],
    [ spectrum,     "spectrum" ],
    [ prism_circle, "prism_circle" ],
    [ rogue_pack,   "rogue_pack" ],
    [ flux,         "flux" ],
    [ echo_shard,   "echo_shard" ],
    [ static_burst, "static_burst" ],
    [ delta_flux,   "delta_flux" ]
  ].each { |group, filename| attach_avatar(group, FIXTURE_FILES.join("groups/#{filename}.png")) }

  puts "Created 9 groups."

  # ── Group relationships ────────────────────────────────────────────────────
  #
  # Alpha Clan tree:
  #   alpha_clan → spectrum (all)
  #     spectrum → prism_circle (all)
  #       prism_circle → rogue_pack (all)   ← problem edge: rogue_pack leaks into alpha_clan
  #
  # Delta Clan tree:
  #   delta_clan → flux (selected: echo_shard only)
  #     flux → echo_shard (all)
  #     flux → static_burst (all)           ← excluded from delta_clan by selected mode
  #   delta_clan → delta_flux (all)

  GroupGroup.create!(parent_group: alpha_clan,   child_group: spectrum,     inclusion_mode: "all")
  GroupGroup.create!(parent_group: spectrum,     child_group: prism_circle, inclusion_mode: "all")
  GroupGroup.create!(parent_group: prism_circle, child_group: rogue_pack,   inclusion_mode: "all")
  GroupGroup.create!(parent_group: delta_clan,   child_group: flux,         inclusion_mode: "selected",
                     included_subgroup_ids: [ echo_shard.id ])
  GroupGroup.create!(parent_group: flux,         child_group: echo_shard,   inclusion_mode: "all")
  GroupGroup.create!(parent_group: flux,         child_group: static_burst, inclusion_mode: "all")
  GroupGroup.create!(parent_group: delta_clan,   child_group: delta_flux,   inclusion_mode: "all")

  puts "Created 7 group relationships."

  # ── Profiles ──────────────────────────────────────────────────────────────

  stray  = user.profiles.create!(name: "Stray",  pronouns: "they/them", heart_emojis: %w[13_storm_heart 25_shadow_heart],               description: "In rogue_pack — should NOT appear in alpha_clan.")
  ember  = user.profiles.create!(name: "Ember",  pronouns: "she/her",   heart_emojis: %w[26_blossom_heart 33_passionate_heart],         description: "In prism_circle — SHOULD appear in alpha_clan.")
  drift  = user.profiles.create!(name: "Drift",  pronouns: "he/him",                                                                    description: "In flux (direct) — should NOT appear in delta_clan.")
  ripple = user.profiles.create!(name: "Ripple", pronouns: "they/she",  heart_emojis: %w[05_seafoam_heart 11_aqua_heart 20_mist_heart], description: "In flux (direct) — should NOT appear in delta_clan.")
  grove  = user.profiles.create!(name: "Grove",                                                                                         description: "Direct member of alpha_clan.")
  shadow = user.profiles.create!(name: "Shadow", pronouns: "she/they",  heart_emojis: %w[24_inky_heart 30_void_heart],                  description: "Direct member of delta_clan.")
  mirage = user.profiles.create!(name: "Mirage", pronouns: "any/all",   heart_emojis: %w[21_lavender_heart 22_violet_heart],            description: "In echo_shard — SHOULD appear in delta_clan via flux.")
  spark  = user.profiles.create!(name: "Spark",                         heart_emojis: %w[39_dawn_heart 50sunshine_heart],               description: "In static_burst — should NOT appear in delta_clan.")

  [
    [ stray,  "stray" ],
    [ ember,  "ember" ],
    [ drift,  "drift" ],
    [ ripple, "ripple" ],
    [ grove,  "grove" ],
    [ shadow, "shadow" ],
    [ mirage, "mirage" ],
    [ spark,  "spark" ]
  ].each { |profile, filename| attach_avatar(profile, FIXTURE_FILES.join("profiles/#{filename}.png")) }

  puts "Created 8 profiles."

  # ── Group memberships ─────────────────────────────────────────────────────

  GroupProfile.create!(group: rogue_pack,   profile: stray)   # deep exclusion test
  GroupProfile.create!(group: prism_circle, profile: stray)   # repeated profile (stray in two places)
  GroupProfile.create!(group: prism_circle, profile: ember)   # should flow up to alpha_clan
  GroupProfile.create!(group: flux,         profile: drift)   # direct profile — excluded from delta_clan
  GroupProfile.create!(group: flux,         profile: ripple)  # direct profile — excluded from delta_clan
  GroupProfile.create!(group: alpha_clan,   profile: grove)   # direct member of top-level clan
  GroupProfile.create!(group: delta_clan,   profile: shadow)  # direct member of another clan
  GroupProfile.create!(group: echo_shard,   profile: mirage)  # should appear in delta_clan via selected flux
  GroupProfile.create!(group: static_burst, profile: spark)   # should NOT appear in delta_clan

  puts "Created 9 group memberships."
end

puts ""
puts "Done. Phase 1 data seeded for user id 1."
puts ""
puts "Scenario summary:"
puts "  Alpha Clan → Spectrum → Prism Circle → Rogue Pack"
puts "    Grove is a direct member of Alpha Clan."
puts "    Ember is in Prism Circle (should appear in Alpha Clan tree)."
puts "    Stray is in Rogue Pack AND Prism Circle (repeated profile; should appear in Alpha Clan)."
puts "    [Future] override: exclude Rogue Pack from Alpha Clan's view without touching Spectrum."
puts ""
puts "  Delta Clan → Flux [selected: echo_shard only] → Echo Shard / Static Burst"
puts "  Delta Clan → Delta Flux"
puts "    Shadow is a direct member of Delta Clan."
puts "    Mirage is in Echo Shard (SHOULD appear in Delta Clan — echo_shard is selected)."
puts "    Drift and Ripple are direct Flux members (should NOT appear in Delta Clan)."
puts "    Spark is in Static Burst (should NOT appear in Delta Clan — not selected)."
