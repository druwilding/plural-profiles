module JournalHelper
  # Dreamwidth's own words for each security level, as on its posting page.
  SECURITY_LABELS = Journal::EntryForm::SECURITY_OPTIONS.merge("custom" => "Custom Filter").freeze

  # Sets the page title, loads journal.css (only journal pages do), and stops
  # Turbo prefetching this page's links: every journal page asks Dreamwidth
  # for something, so a hover mustn't.
  #
  # "dynamic" lets Turbo add the stylesheet arriving on a journal page and
  # remove it leaving, with no full page reload either way.
  def journal_page(title)
    content_for(:title) { "#{title} — Plural Profiles" }
    content_for(:head) do
      stylesheet_link_tag("journal", "data-turbo-track": "dynamic") +
        tag.meta(name: "turbo-prefetch", content: "false")
    end
  end

  # Journal addresses use hyphens where usernames have underscores.
  def dreamwidth_journal_url(username)
    "https://#{username.tr('_', '-')}.dreamwidth.org/"
  end

  # Links to Dreamwidth open in a new tab, since they leave Plural Profiles.
  # Marked with ↗ the way the site marks its other new-tab links, plus words
  # for screen readers, which skip the arrow.
  def dreamwidth_link_to(url, **options, &block)
    link_to url, target: "_blank", rel: "noopener", **options do
      safe_join([
        capture(&block),
        " ",
        tag.span("↗", aria: { hidden: "true" }),
        tag.span(" (opens in a new tab)", class: "visually-hidden")
      ])
    end
  end

  # A journal named the way Dreamwidth names one: its userhead icon (a person,
  # or a globe for a community), then the username in bold, linking to the
  # journal. The icon is decoration; the name says it all. The icons are our
  # own copies, credited in app/assets/images/dreamwidth/README.md.
  def dreamwidth_journal_link(username, community: false)
    userhead = community ? "dreamwidth/community.png" : "dreamwidth/user.png"
    dreamwidth_link_to dreamwidth_journal_url(username), class: "dreamwidth-journal-link" do
      image_tag(userhead, alt: "", class: "dreamwidth-journal-link__userhead", width: 16, height: 16) +
        tag.strong(username)
    end
  end

  def dreamwidth_security_label(security)
    SECURITY_LABELS.fetch(security.to_s, security.to_s.humanize)
  end

  # The Icon dropdown: "(default)" first, then every keyword. Each option
  # carries its icon's image address, for the preview to show.
  def journal_icon_options(icons, default_icon_url, selected)
    options = [ [ "(default)", "", { data: { url: default_icon_url } } ] ] +
      icons.map { |keyword, url| [ keyword, keyword, { data: { url: url } } ] }
    options_for_select(options, selected)
  end

  # The journal's tags for the suggestions on the Write page. json_escape
  # keeps a tag like "</script>" from ending the script early.
  def journal_tags_json_tag(tags)
    tag.script(json_escape(tags.to_json).html_safe, type: "application/json", data: { "journal-tags-target": "list" })
  end

  # A username that can wrap after its underscores ("example_" / "journal"),
  # rather than mid-word, where space is tight.
  def journal_wrappable_username(username)
    safe_join(username.split(/(?<=_)/).flat_map { |part| [ part, tag.wbr ] }[0...-1])
  end

  # Who can see an entry, in a sentence, as Dreamwidth says it after posting.
  def dreamwidth_entry_visibility(security)
    case security.to_s
    when "public" then "The entry is visible to everyone."
    when "access" then "The entry is visible to your access list."
    when "private" then "The entry is private: only you can see it."
    when "custom" then "The entry is visible to your custom access filters."
    else "The entry's security is “#{security}”."
    end
  end

  # Dreamwidth's "2026-10-06 21:34:00" is the journal's own local time with no
  # zone, so it's shown as is, never converted.
  def dreamwidth_entry_date(datetime)
    DateTime.strptime(datetime.to_s, "%Y-%m-%d %H:%M:%S").strftime("%-d %B %Y, %H:%M")
  rescue Date::Error
    datetime.to_s
  end
end
