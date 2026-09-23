# Phase 1 seed script — checkbox-model test scenario
# Run with: bin/rails runner script/phase1_seed.rb
#
# Creates the full group/profile hierarchy under a new user.
# Safe to re-run: wraps everything in a transaction and skips if alpha_clan already exists.

FIXTURE_FILES = Rails.root.join("test/fixtures/files")

def attach_avatar(record, path)
  record.avatar.attach(
    io: File.open(path),
    filename: File.basename(path),
    content_type: "image/png"
  )
end

random_email    = "phase1-#{SecureRandom.hex(6)}@example.com"
random_password = SecureRandom.hex(12)

user = User.create!(
  email_address:    random_email,
  password:         random_password,
  password_confirmation: random_password,
  email_verified_at: Time.current
)

puts "Seeding for new user #{user.email_address} (id #{user.id})."

ActiveRecord::Base.transaction do
  # ── Groups ────────────────────────────────────────────────────────────────

  alpha_clan   = user.groups.create!(name: "Alpha Clan",   description: "A clan at the top of the tree.")
  castle_clan  = user.groups.create!(name: "Castle Clan",  description: "Another clan.")
  spectrum     = user.groups.create!(name: "Spectrum",     description: "Overarching category spanning clans.")
  prism_circle = user.groups.create!(name: "Prism Circle", description: "Sub-category inside Spectrum.", avatar_shape: "circle")
  rogue_pack   = user.groups.create!(name: "Rogue Pack",   description: "Sub-group of Prism Circle; its own independent clan.")
  flux         = user.groups.create!(name: "Flux",         description: "Category spanning multiple clans.")
  echo_shard   = user.groups.create!(name: "Echo Shard",   description: "Sub-group of Flux.")
  static_burst = user.groups.create!(name: "Static Burst", description: "Another sub-group of Flux.")
  castle_flux  = user.groups.create!(name: "Castle Flux",  description: "Flux section specific to Castle Clan.")

  [
    [ alpha_clan,   "alpha_clan" ],
    [ castle_clan,   "castle_clan" ],
    [ spectrum,     "spectrum" ],
    [ prism_circle, "prism_circle" ],
    [ rogue_pack,   "rogue_pack" ],
    [ flux,         "flux" ],
    [ echo_shard,   "echo_shard" ],
    [ static_burst, "static_burst" ],
    [ castle_flux,   "castle_flux" ]
  ].each { |group, filename| attach_avatar(group, FIXTURE_FILES.join("groups/#{filename}.png")) }

  puts "Created 9 groups."

  # ── Group relationships ────────────────────────────────────────────────────
  #
  # Alpha Clan tree (with diamond — Prism Circle reachable via two paths):
  #   alpha_clan → spectrum
  #     spectrum → prism_circle
  #       prism_circle → rogue_pack
  #   alpha_clan → echo_shard
  #     echo_shard → prism_circle  (same group, different path)
  #       prism_circle → rogue_pack  (same edge, different ancestor path)
  #
  # Castle Clan tree:
  #   castle_clan → flux
  #     flux → echo_shard
  #     flux → static_burst
  #   castle_clan → castle_flux

  GroupGroup.create!(parent_group: alpha_clan,   child_group: spectrum)
  GroupGroup.create!(parent_group: spectrum,     child_group: prism_circle)
  GroupGroup.create!(parent_group: prism_circle, child_group: rogue_pack)
  GroupGroup.create!(parent_group: castle_clan,   child_group: flux)
  GroupGroup.create!(parent_group: flux,         child_group: echo_shard)
  GroupGroup.create!(parent_group: flux,         child_group: static_burst)
  GroupGroup.create!(parent_group: castle_clan,   child_group: castle_flux)
  # Diamond path: Echo Shard also under Alpha Clan
  GroupGroup.create!(parent_group: alpha_clan,   child_group: echo_shard)
  GroupGroup.create!(parent_group: echo_shard,   child_group: prism_circle)

  puts "Created 9 group relationships."

  # ── Profiles ──────────────────────────────────────────────────────────────

  stray  = user.profiles.create!(name: "Stray",  pronouns: "they/them", emotes: ":storm_heart: :shadow_heart:",           description: "In Prism Circle & Rogue Pack — should NOT appear in Alpha Clan (excluded by profile override).", avatar_shape: "circle")
  ember  = user.profiles.create!(name: "Ember",  pronouns: "she/her",   emotes: ":blossom_heart: :passionate_heart:",     description: "In Prism Circle — SHOULD appear in Alpha Clan (selected in profile override).")
  drift  = user.profiles.create!(name: "Drift",  pronouns: "he/him",                                                         description: "In Flux (direct) — should NOT appear in Castle Clan.")
  ripple = user.profiles.create!(name: "Ripple", pronouns: "they/she",  emotes: ":seafoam_heart: :aqua_heart: :mist_heart:", description: "In Flux (direct) — should NOT appear in Castle Clan.")
  grove  = user.profiles.create!(name: "Grove",                                                                              description: "Direct member of Alpha Clan.", avatar_shape: "square")
  shadow = user.profiles.create!(name: "Shadow", pronouns: "she/they",  emotes: ":inky_heart: :void_heart:",             description: "Direct member of Castle Clan.", avatar_shape: "circle")
  mirage = user.profiles.create!(name: "Mirage", pronouns: "any/all",   emotes: ":lavender_heart: :violet_heart:",       description: "In Echo Shard — SHOULD appear in Castle Clan via Flux.")
  spark  = user.profiles.create!(name: "Spark",                         emotes: ":dawn_heart: :sunshine_heart:",         description: "In Static Burst — should NOT appear in Castle Clan.")

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

  # ── Inclusion overrides (checkbox model) ─────────────────────────────────
  #
  # Overrides hide specific items at specific paths within a root group's tree.
  # path = array of group IDs from root (exclusive) to the group containing the target (inclusive).
  #
  # Alpha Clan overrides:
  #   - Hide Rogue Pack at path [spectrum, prism_circle] (but visible via echo_shard path)
  #   - Hide Stray at path [spectrum, prism_circle, rogue_pack] (but visible via echo_shard path)
  #
  # Castle Clan overrides:
  #   - Hide Static Burst at path [flux]
  #   - Hide Drift at path [flux]
  #   - Hide Ripple at path [flux]

  InclusionOverride.create!(
    group: alpha_clan,
    path: [ spectrum.id, prism_circle.id ],
    target_type: "Group",
    target_id: rogue_pack.id
  )

  InclusionOverride.create!(
    group: alpha_clan,
    path: [ spectrum.id, prism_circle.id, rogue_pack.id ],
    target_type: "Profile",
    target_id: stray.id
  )

  InclusionOverride.create!(
    group: castle_clan,
    path: [ flux.id ],
    target_type: "Group",
    target_id: static_burst.id
  )

  InclusionOverride.create!(
    group: castle_clan,
    path: [ flux.id ],
    target_type: "Profile",
    target_id: drift.id
  )

  InclusionOverride.create!(
    group: castle_clan,
    path: [ flux.id ],
    target_type: "Profile",
    target_id: ripple.id
  )

  puts "Created 5 inclusion overrides."

  # ── Group memberships ─────────────────────────────────────────────────────

  GroupProfile.create!(group: rogue_pack,   profile: stray)   # deep exclusion test
  GroupProfile.create!(group: prism_circle, profile: stray)   # repeated profile (stray in two places)
  GroupProfile.create!(group: prism_circle, profile: ember)   # should flow up to alpha_clan
  GroupProfile.create!(group: flux,         profile: drift)   # direct profile — excluded from castle_clan
  GroupProfile.create!(group: flux,         profile: ripple)  # direct profile — excluded from castle_clan
  GroupProfile.create!(group: alpha_clan,   profile: grove)   # direct member of top-level clan
  GroupProfile.create!(group: castle_clan,   profile: shadow) # direct member of another clan
  GroupProfile.create!(group: echo_shard,   profile: mirage)  # should appear in castle_clan via selected flux
  GroupProfile.create!(group: static_burst, profile: spark)   # should NOT appear in castle_clan

  puts "Created 9 group memberships."

  # ── Chat proxy brackets ───────────────────────────────────────────────────
  #
  # A few different bracket styles, so the composer's proxy-detection has
  # something to exercise: prefix-only, prefix+suffix wrap, and suffix-only.
  # Matching is case-sensitive, so these only ever need to be unique as typed.

  stray.update!(chat_bracket_before: "stray:")                       # prefix-only, e.g. "stray: on the hunt"
  ember.update!(chat_bracket_before: "{", chat_bracket_after: "}")   # wrap, e.g. "{lighting up the room}"
  drift.update!(chat_bracket_after: "~drift")                        # suffix-only, e.g. "just passing through~drift"

  puts "Set chat proxy brackets on Stray, Ember, and Drift."

  # ── Chat server ───────────────────────────────────────────────────────────

  server = user.owned_chat_servers.create!(name: "The Warren", description: "A quiet place to check in.")
  server.memberships.create!(user: user, role: "owner", default_postable: grove)

  general  = server.channels.create!(name: "general",   description: "Say hello.")
  checkins = server.channels.create!(name: "check-ins", description: "How's everyone doing?")
  spoilers = server.channels.create!(name: "spoilers",   description: "Wrap anything sensitive in ||spoiler tags||.")

  puts "Created chat server \"The Warren\" with #{[ general, checkins, spoilers ].size} channels."

  # ── Example messages ──────────────────────────────────────────────────────
  #
  # Relative-to-now timestamps, from a mix of profiles. Some post via an
  # explicit profile; the "stray:", "{...}", and "~drift"-suffixed ones
  # deliberately omit profile so Profile.resolve_chat_proxy picks it from the
  # brackets instead (and strips them from the stored body), same as a real
  # user typing them in the composer.

  general.messages.create!(user: user, postable: grove, body: "Hey everyone, welcome to The Warren!", created_at: 3.days.ago)
  general.messages.create!(user: user, body: "stray: just wandered in, hi all", created_at: 2.days.ago)
  general.messages.create!(user: user, body: "{waves from the doorway}", created_at: 1.day.ago)
  general.messages.create!(user: user, postable: shadow, body: "Good to see this place coming together.", created_at: 5.hours.ago)
  general.messages.create!(user: user, postable: grove, body: "Anyone free to chat later?", created_at: 20.minutes.ago)

  checkins.messages.create!(user: user, postable: mirage, body: "Feeling pretty good today, thanks for asking.", created_at: 1.day.ago)
  checkins.messages.create!(user: user, body: "doing okay, just tired~drift", created_at: 6.hours.ago)
  checkins.messages.create!(user: user, postable: ripple, body: "Same as always — steady.", created_at: 45.minutes.ago)

  spoilers.messages.create!(user: user, postable: spark, body: "||Big reveal coming up in the movie||[The Odyssey]", created_at: 2.days.ago)
  spoilers.messages.create!(user: user, postable: grove, body: "||Oh wow, i can't wait to see how that plays out||", created_at: 3.hours.ago)

  puts "Created 10 example chat messages."
end

puts ""
puts "Done. Data seeded for #{user.email_address} (id #{user.id})."
puts ""
puts "Scenario summary:"
puts "  Alpha Clan → Spectrum → Prism Circle → Rogue Pack"
puts "  Alpha Clan → Echo Shard → Prism Circle → Rogue Pack  (diamond — same groups, different path)"
puts "    Grove is a direct member of Alpha Clan."
puts "    Ember is in Prism Circle (visible from Alpha Clan)."
puts "    Stray is in Rogue Pack AND Prism Circle."
puts "    Override: Rogue Pack hidden at path [spectrum, prism_circle]."
puts "    Override: Stray hidden at path [spectrum, prism_circle, rogue_pack]."
puts "    → Via Spectrum: Rogue Pack excluded, Stray excluded."
puts "    → Via Echo Shard: Rogue Pack and Stray both visible."
puts ""
puts "  Castle Clan → Flux → Echo Shard / Static Burst"
puts "  Castle Clan → Castle Flux"
puts "    Shadow is a direct member of Castle Clan."
puts "    Mirage is in Echo Shard (visible in Castle Clan via Flux)."
puts "    Override: Static Burst hidden at path [flux]."
puts "    Override: Drift hidden at path [flux]."
puts "    Override: Ripple hidden at path [flux]."
puts "    → Spark (in Static Burst) excluded from Castle Clan."
puts "    → Drift and Ripple (direct Flux members) excluded from Castle Clan."
puts ""
puts "  Chat: server \"The Warren\" with #general, #check-ins, and #spoilers."
puts "    Posting as Grove by default."
puts "    Stray: prefix bracket \"stray:\" (e.g. \"stray: on the hunt\")"
puts "    Ember: wrap brackets \"{\" / \"}\" (e.g. \"{lighting up the room}\")"
puts "    Drift: suffix bracket \"~drift\" (e.g. \"just passing through~drift\")"
puts "    10 example messages seeded across the three channels, most recent 20 minutes ago."
puts ""
puts "────────────────────────────────"
puts "Login credentials:"
puts "  Email:    #{user.email_address}"
puts "  Password: #{random_password}"
puts "────────────────────────────────"
