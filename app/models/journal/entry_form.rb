module Journal
  # What someone typed on the Write page, kept exactly as typed, so a post
  # that fails comes back with nothing lost. Turns it into what Dreamwidth's
  # API takes.
  class EntryForm
    include ActiveModel::Model
    include ActiveModel::Attributes

    # Dreamwidth's own limit; it rejects longer tags.
    MAX_TAG_LENGTH = 40

    # What "Show this entry to" can be, in Dreamwidth's words. Custom filters
    # join once Dreamwidth's API accepts them.
    SECURITY_OPTIONS = {
      "public" => "Everyone (Public)",
      "access" => "Access List",
      "private" => "Private (Just You)"
    }.freeze

    attribute :subject, :string, default: ""
    attribute :body, :string, default: ""
    attribute :tags, :string, default: ""
    # An icon keyword, or blank for the journal's default icon.
    attribute :icon, :string, default: ""
    attribute :security, :string, default: "private"
    # "YYYY-MM-DDTHH:MM" in the person's own time zone, from the date fields.
    attribute :datetime, :string
    # What the date fields started as. If they weren't changed, no datetime
    # is sent and Dreamwidth uses its own "now", so a page left open for an
    # hour still posts at the time it's posted.
    attribute :datetime_original, :string

    validates :body, presence: { message: "can't be empty" }
    validates :security, inclusion: { in: ->(_form) { security_options.keys }, message: "isn't one of the options" }
    validate :datetime_is_a_date
    validate :tags_fit

    def self.security_options
      Journal::PRIVATE_ONLY ? SECURITY_OPTIONS.slice("private") : SECURITY_OPTIONS
    end

    def self.human_attribute_name(attribute, options = {})
      { body: "Entry text", datetime: "Date" }.fetch(attribute.to_sym) { super }
    end

    def tag_list
      tags.to_s.split(",").map(&:strip).compact_blank.uniq
    end

    # The date fields as a time, for filling them in again.
    def datetime_value
      (datetime.present? && Time.zone.parse(datetime)) || Time.zone.now
    end

    def to_api
      {
        subject: subject.presence,
        text: body,
        security: security,
        tags: tag_list,
        icon: icon.presence,
        datetime: changed_datetime
      }.compact
    end

    private

    def changed_datetime
      return if datetime.blank? || datetime == datetime_original

      datetime.tr("T", " ")
    end

    def datetime_is_a_date
      errors.add(:datetime, "isn't a real date") if datetime.blank? && datetime_original.present?
    end

    def tags_fit
      tag_list.select { |tag| tag.length > MAX_TAG_LENGTH }.each do |tag|
        errors.add(:tags, "can be up to #{MAX_TAG_LENGTH} characters each, and \"#{tag.truncate(50)}\" is #{tag.length}")
      end
    end
  end
end
