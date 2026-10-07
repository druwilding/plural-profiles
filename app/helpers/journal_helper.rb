module JournalHelper
  # Dreamwidth's own words for each security level, as on its posting page.
  SECURITY_LABELS = {
    "public" => "Everyone (Public)",
    "access" => "Access List",
    "private" => "Private (Just You)",
    "custom" => "Custom Filter"
  }.freeze

  DREAMWIDTH_USERHEAD_URL = "https://www.dreamwidth.org/img/silk/identity/user.png".freeze

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

  # A journal named the way Dreamwidth names one: its userhead icon, then the
  # username in bold, linking to the journal. The icon is decoration; the
  # name says it all.
  def dreamwidth_journal_link(username)
    dreamwidth_link_to dreamwidth_journal_url(username), class: "dreamwidth-journal-link" do
      image_tag(DREAMWIDTH_USERHEAD_URL, alt: "", class: "dreamwidth-journal-link__userhead", width: 17, height: 17) +
        tag.strong(username)
    end
  end

  def dreamwidth_security_label(security)
    SECURITY_LABELS.fetch(security.to_s, security.to_s.humanize)
  end

  # Dreamwidth's "2026-10-06 21:34:00" is the journal's own local time with no
  # zone, so it's shown as is, never converted.
  def dreamwidth_entry_date(datetime)
    DateTime.strptime(datetime.to_s, "%Y-%m-%d %H:%M:%S").strftime("%-d %B %Y, %H:%M")
  rescue Date::Error
    datetime.to_s
  end
end
