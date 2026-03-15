module HasLabels
  extend ActiveSupport::Concern

  included do
    before_validation :normalize_labels
  end

  # Returns labels as a comma-separated string, for use in text fields.
  def labels_text
    labels.join(", ")
  end

  # Accepts a comma-separated string and populates the labels array.
  def labels_text=(value)
    self.labels = value.to_s.split(",").map(&:strip).reject(&:blank?).uniq
  end

  private

  def normalize_labels
    self.labels = Array(labels).map { |l| l.to_s.strip }.reject(&:blank?).uniq
  end
end
