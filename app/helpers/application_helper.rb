module ApplicationHelper
  DESCRIPTION_EXTRA_TAGS = %w[details summary].to_set.freeze
  DESCRIPTION_EXTRA_ATTRIBUTES = %w[open].to_set.freeze

  def formatted_description(text)
    safe_list_class = self.class.safe_list_sanitizer.class
    tags = safe_list_class.allowed_tags + DESCRIPTION_EXTRA_TAGS
    attrs = safe_list_class.allowed_attributes + DESCRIPTION_EXTRA_ATTRIBUTES
    simple_format(text, {}, sanitize_options: { tags: tags, attributes: attrs })
  end
end
