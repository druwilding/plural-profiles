module Dreamwidth
  # An entry as Dreamwidth reports it. Subject and body are the raw source,
  # exactly as typed: Dreamwidth includes those when the key can edit the
  # entry, and editing from the rendered HTML would convert someone's markup.
  # So body is nil rather than ever falling back to the rendered version.
  #
  # datetime is the journal's own local time ("2026-10-06 21:34:00") with no
  # time zone, so it's kept as Dreamwidth's text and never converted.
  Entry = Data.define(:id, :url, :subject, :body, :datetime, :security, :tags, :icon_keyword) do
    def self.from_api(hash)
      new(
        id: hash.fetch("entry_id"),
        url: hash["url"],
        subject: hash["subject_raw"] || hash["subject"].to_s,
        body: hash["body_raw"],
        datetime: hash["datetime"],
        security: hash["security"],
        tags: Array(hash["tags"]),
        icon_keyword: hash["icon_keyword"]
      )
    end
  end
end
