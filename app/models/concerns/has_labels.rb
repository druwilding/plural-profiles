module HasLabels
  extend ActiveSupport::Concern

  included do
    before_validation :normalize_labels

    # Order by name, then unlabelled items first, then labels alphabetically.
    scope :order_by_name_and_labels, -> {
      order(Arel.sql("name, CASE WHEN labels = '[]'::jsonb THEN 0 ELSE 1 END, labels::text"))
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

  # Sort key for in-memory ordering: name first, unlabelled before labelled,
  # then labels alphabetically.
  def name_and_label_sort_key
    [ name, labels.empty? ? 0 : 1, labels.join(", ") ]
  end

  private

  def normalize_labels
    self.labels = Array(labels).map { |l| l.to_s.strip }.reject(&:blank?).uniq
  end
end
