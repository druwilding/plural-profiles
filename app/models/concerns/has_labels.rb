module HasLabels
  extend ActiveSupport::Concern

  included do
    before_validation :normalize_labels

    # Order by name (case-insensitive), then unlabelled items first, then labels alphabetically.
    # COLLATE "C" sorts by raw codepoint (byte) order rather than the database's locale-aware
    # collation, so leading punctuation participates in ordering (instead of being ignored in
    # some locales) — matching the in-memory ordering from #name_and_label_sort_key.
    # Columns are qualified so the scope also works on queries joined to a link table.
    scope :order_by_name_and_labels, -> {
      table = quoted_table_name
      order(Arel.sql(%Q{LOWER(#{table}.name) COLLATE "C", CASE WHEN #{table}.labels = '[]'::jsonb THEN 0 ELSE 1 END, LOWER(#{table}.labels::text) COLLATE "C"}))
    }
  end

  # Returns labels as a comma-separated string, for use in text fields.
  def labels_text
    labels.join(", ")
  end

  # Accepts a comma-separated string and populates the labels array.
  def labels_text=(value)
    self.labels = value.to_s.split(",").map(&:strip).reject(&:blank?).uniq
  end

  # Sort key for in-memory ordering: name first (case-insensitive), unlabelled before labelled,
  # then labels alphabetically.
  def name_and_label_sort_key
    [ name.downcase, labels.empty? ? 0 : 1, labels.join(", ").downcase ]
  end

  private

  def normalize_labels
    self.labels = Array(labels).map { |l| l.to_s.strip }.reject(&:blank?).uniq
  end
end
