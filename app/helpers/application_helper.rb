module ApplicationHelper
  DESCRIPTION_EXTRA_TAGS = %w[details summary span].to_set.freeze
  DESCRIPTION_EXTRA_ATTRIBUTES = %w[open class role tabindex aria-label aria-expanded].to_set.freeze

  SPOILER_PATTERN = /\|\|(.+?)\|\|/m
  CODE_BLOCK_PATTERN = /<code>.*?<\/code>/m

  SPOILER_REPLACEMENT = '<span class="spoiler" role="button" tabindex="0" ' \
    'aria-expanded="false" aria-label="Hidden content, click to reveal">\1</span>'

  def formatted_description(text)
    safe_list_class = self.class.safe_list_sanitizer.class
    tags = safe_list_class.allowed_tags + DESCRIPTION_EXTRA_TAGS
    attrs = safe_list_class.allowed_attributes + DESCRIPTION_EXTRA_ATTRIBUTES
    text = convert_spoilers_outside_code(text)
    html = simple_format(text, {}, sanitize_options: { tags: tags, attributes: attrs })
    html.gsub("</details>", '<button type="button" class="details-close" aria-label="Close details">(click to close)</button></details>').html_safe
  end

  def relative_time(time)
    return "unknown" unless time
    if time.future?
      "#{distance_of_time_in_words(Time.current, time)} from now"
    else
      "#{time_ago_in_words(time)} ago"
    end
  end

  private

  def convert_spoilers_outside_code(text)
    # Split on <code>...</code> blocks so we only convert ||text|| outside them
    parts = text.split(CODE_BLOCK_PATTERN)
    code_blocks = text.scan(CODE_BLOCK_PATTERN)

    result = parts.map { |part| part.gsub(SPOILER_PATTERN, SPOILER_REPLACEMENT) }
    code_blocks.each_with_index { |block, i| result.insert((i * 2) + 1, block) }
    result.join
  end
end
