# Every emote, loaded from the database once and kept in plain Ruby lookups so
# rendering formatted text (every chat message, every profile field) never
# queries emotes directly.
#
# The built registry is shared by all threads in the process and rebuilt only
# when the database's emote version changes. The version is checked once per
# request (it's memoised in Current), with a single cheap query, so edits made
# in one process reach every other process on its next request. The cache store
# is per-process (memory_store), so a Rails.cache counter wouldn't do that.
class EmoteRegistry
  Entry = Data.define(:id, :name, :code, :label, :src, :emote_set_id, :archived) do
    alias_method :archived?, :archived
  end
  # Not called Set, which would hide Ruby's ::Set inside this class.
  SetEntry = Data.define(:id, :name, :position)

  # A typed code: a delimiter (: or ;) and a name, with the closing delimiter
  # only looked ahead at. See #replace_codes for why it isn't consumed here.
  CODE_PATTERN = /[:;]([a-z0-9][a-z0-9_-]*)(?=[:;])/i

  # A number before the name, e.g. the "11-" in "11-aqua-heart" or the "50" in
  # "50cadbury-heart": old Discord-numbered pastes. Only stripped when a letter
  # follows, so "100" is never reduced to "00".
  LEGACY_NUMBER_PREFIX = /\A\d+-?(?=[a-z])/

  VERSION_SQL = <<~SQL.squish.freeze
    SELECT concat_ws('/',
      (SELECT count(*) FROM emote_sets), (SELECT max(updated_at) FROM emote_sets),
      (SELECT count(*) FROM emotes), (SELECT max(updated_at) FROM emotes),
      (SELECT count(*) FROM emote_aliases), (SELECT max(updated_at) FROM emote_aliases))
  SQL

  @mutex = Mutex.new
  @built = nil

  class << self
    # The site-wide registry. Future scoped emotes would add
    # EmoteRegistry.for(server:, user:), merging site entries with the scope's.
    def current
      Current.emote_registry ||= begin
        version = ActiveRecord::Base.connection.select_value(VERSION_SQL)
        @mutex.synchronize do
          @built = build(version) unless @built&.version == version
          @built
        end
      end
    end

    # Called after any emote change is committed, so the rest of this request
    # (e.g. re-rendering after an admin edit) sees it.
    def expire_current
      Current.emote_registry = nil
    end

    private

    def build(version)
      emote_sets = EmoteSet.site_wide.ordered.map do |emote_set|
        SetEntry.new(id: emote_set.id, name: emote_set.name, position: emote_set.position)
      end
      set_order = emote_sets.each_with_index.to_h { |emote_set, index| [ emote_set.id, index ] }

      emotes = Emote.joins(:emote_set).merge(EmoteSet.site_wide)
        .includes(:aliases, image_attachment: :blob).to_a
      emotes.sort_by! { |emote| [ set_order.fetch(emote.emote_set_id, emote_sets.size), Emote.natural_sort_key(emote.name), emote.name ] }

      new(version: version, emote_sets: emote_sets, emotes: emotes)
    end
  end

  attr_reader :version, :emote_sets, :entries

  def initialize(version:, emote_sets:, emotes:)
    @version = version
    @emote_sets = emote_sets.freeze
    @emote_sets_by_id = @emote_sets.index_by(&:id)
    @entries = emotes.map { |emote| entry_for(emote) }.freeze
    @by_name = @entries.index_by(&:name)
    @by_code = @entries.index_by(&:code)
    @by_alias = emotes.each_with_object({}) do |emote, lookup|
      emote.aliases.each { |emote_alias| lookup[emote_alias.code] = @by_code[emote.code] }
    end
  end

  # Entries that can be offered in pickers and autocomplete. Archived emotes
  # still resolve (so existing text keeps rendering) but aren't offered.
  def pickable
    @pickable ||= entries.reject(&:archived?)
  end

  # Finds the emote for a typed code: its name (:02-spring-heart:, :100:), its
  # code (:spring-heart:), an old code (alias), or, for old Discord-numbered
  # pastes, any of those after the number (:11-aqua-heart:). Case and
  # underscores-for-hyphens don't matter, so codes written before identifiers
  # switched to hyphens (:spring_heart:) keep working.
  def resolve(raw)
    key = Emote.normalize_identifier(raw)
    return if key.empty?

    lookup(key) || begin
      bare = key.sub(LEGACY_NUMBER_PREFIX, "")
      lookup(bare) if bare != key
    end
  end

  def emote_set(id)
    @emote_sets_by_id[id]
  end

  # Replaces every code in text that resolves to an emote with the block's
  # result for that emote; everything else is left exactly as it was.
  # Delimiters (: or ;) and separators (_ or -) can be mixed, e.g.
  # :cadbury-heart:, ;cadbury_heart;, :cadbury-heart;
  #
  # The closing delimiter is only consumed when the code resolves. Otherwise an
  # unknown code would swallow the delimiter that opens the next real one: in
  # "12:30:red-heart:", ":30" isn't an emote, so its closing colon is left to
  # open ":red-heart:".
  def replace_codes(text)
    result = +""
    position = 0
    while (match = CODE_PATTERN.match(text, position))
      emote = resolve(match[1])
      if emote
        result << text[position...match.begin(0)] << yield(emote)
        position = match.end(0) + 1
      else
        result << text[position...match.end(0)]
        position = match.end(0)
      end
    end
    result << text[position..]
  end

  private

  def lookup(key)
    @by_name[key] || @by_code[key] || @by_alias[key]
  end

  def entry_for(emote)
    Entry.new(
      id: emote.id,
      name: emote.name,
      code: emote.code,
      label: emote.code.tr("-", " "),
      src: emote.display_image_path,
      emote_set_id: emote.emote_set_id,
      archived: emote.archived?
    )
  end
end
