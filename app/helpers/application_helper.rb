module ApplicationHelper
  DESCRIPTION_EXTRA_TAGS = %w[details summary span].to_set.freeze
  DESCRIPTION_EXTRA_ATTRIBUTES = %w[open class].to_set.freeze

  SPOILER_PATTERN = /\|\|(.+?)\|\|/

  def formatted_description(text)
    safe_list_class = self.class.safe_list_sanitizer.class
    tags = safe_list_class.allowed_tags + DESCRIPTION_EXTRA_TAGS
    attrs = safe_list_class.allowed_attributes + DESCRIPTION_EXTRA_ATTRIBUTES
    text = text.gsub(SPOILER_PATTERN, '<span class="spoiler">\1</span>')
    simple_format(text, {}, sanitize_options: { tags: tags, attributes: attrs })
  end
end
