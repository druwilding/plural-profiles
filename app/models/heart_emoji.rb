# The heart emojis that can be picked for a profile's hearts or typed as codes
# (:cadbury_heart:) into any formatted text field. Not tied to any one model —
# profiles store picked hearts, but codes render in chat messages, server and
# channel names, groups, and so on.
module HeartEmoji
  # Order here is the display order everywhere hearts are listed: the profile
  # form, the heart picker dialog, and autocomplete results. Numbers are not
  # part of the stored/canonical name — Discord's numbering churns as hearts
  # are added, so heart_emojis and emoji codes in text are keyed on the name
  # alone.
  ALL = [
    "dewdrop_heart",
    "spring_heart",
    "hunter_heart",
    "woods_heart",
    "seafoam_heart",
    "fern_heart",
    "moss_heart",
    "bramble_heart",
    "wild_heart",
    "aqua_heart",
    "ocean_heart",
    "storm_heart",
    "abyss_heart",
    "frozen_heart",
    "ice_heart",
    "cornflower_heart",
    "azure_heart",
    "nightsky_heart",
    "haunted_heart",
    "mist_heart",
    "lavender_heart",
    "violet_heart",
    "aubegine_heart",
    "shadow_heart",
    "inky_heart",
    "blossom_heart",
    "burgundy_heart",
    "arcane_heart",
    "void_heart",
    "vulnerable_heart",
    "filthy_heart",
    "passionate_heart",
    "blackened_heart",
    "hungry_heart",
    "princess_heart",
    "red_heart",
    "murder_heart",
    "dawn_heart",
    "peach_heart",
    "tangerine_heart",
    "bone_heart",
    "fawn_heart",
    "fur_heart",
    "soil_heart",
    "sunlit_heart",
    "lemondrop_heart",
    "nox_heart",
    "cadbury_heart",
    "maroon_heart",
    "sunshine_heart"
  ].freeze

  # Delimiters (: or ;) and the internal word separator (_ or -) can each be
  # mixed independently, e.g. :cadbury_heart:, ;cadbury-heart;, :cadbury_heart;
  PATTERN = /[:;]([a-z0-9_-]+[_-]heart)[:;]/i

  # Resolve a heart name to its canonical ALL entry, or nil if it isn't one.
  # Accepts both the bare name ("aqua_heart") and older pastes that still carry
  # a number prefix ("11_aqua_heart") — the number is stripped and ignored, since
  # Discord's numbering has changed under us before and will again. Also
  # accepts hyphens in place of underscores ("aqua-heart"), since typed heart
  # codes allow either separator.
  def self.resolve(name)
    bare = name.to_s.downcase.sub(/\A\d+[_-]?/, "").tr("-", "_")
    bare if ALL.include?(bare)
  end

  # "cadbury_heart" → "cadbury heart"
  def self.display_name(heart)
    heart.tr("_", " ")
  end

  def self.image_path(heart)
    "/images/hearts/#{heart}.webp"
  end

  # The canonical code as typed into text, e.g. ":cadbury_heart:". Semicolons
  # and hyphens are accepted on input, but inserted codes always use this form.
  def self.code(heart)
    ":#{heart}:"
  end
end
