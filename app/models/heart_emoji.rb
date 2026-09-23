# Transitional facade over EmoteRegistry, keeping the interface that views,
# helpers and Profile used when hearts were a hardcoded list. Emotes now live
# in the database (Emote, EmoteGroup, EmoteAlias); this module goes away once
# callers use the registry directly.
module HeartEmoji
  # Every pickable emote's canonical code, in display order: the profile
  # form, the heart picker dialog, and autocomplete results.
  def self.all
    EmoteRegistry.current.pickable.map(&:code)
  end

  # Resolve a typed name to its canonical code, or nil if it isn't an emote.
  # See EmoteRegistry#resolve for the accepted forms.
  def self.resolve(name)
    EmoteRegistry.current.resolve(name)&.code
  end

  # "cadbury_heart" → "cadbury heart"
  def self.display_name(heart)
    heart.tr("_", " ")
  end

  def self.image_path(heart)
    EmoteRegistry.current.resolve(heart)&.src
  end

  # The canonical code as typed into text, e.g. ":cadbury_heart:". Semicolons
  # and hyphens are accepted on input, but inserted codes always use this form.
  def self.code(heart)
    ":#{heart}:"
  end
end
