class Our::SearchController < ApplicationController
  include OurSidebar

  # Each also matches the chat-identity override columns (mini_profile_*) —
  # someone might only remember what a group/profile is called or described
  # as *in chat*, not the main version, and the two can differ once
  # overridden. A blank override column (the common case: still inherited)
  # never matches anything extra, so this is a pure addition, not a
  # behavior change for anyone who hasn't set up chat overrides.
  GROUP_CONDITIONS = <<~SQL.squish.freeze
    name ILIKE :term OR subtitle ILIKE :term OR tag_line ILIKE :term OR description ILIKE :term OR pronouns ILIKE :term
    OR mini_profile_name ILIKE :term OR mini_profile_subtitle ILIKE :term OR mini_profile_tag_line ILIKE :term OR mini_profile_description ILIKE :term OR mini_profile_pronouns ILIKE :term
    OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(labels) AS label_val WHERE label_val ILIKE :term)
  SQL

  PROFILE_CONDITIONS = <<~SQL.squish.freeze
    name ILIKE :term OR subtitle ILIKE :term OR tag_line ILIKE :term OR description ILIKE :term OR pronouns ILIKE :term
    OR mini_profile_name ILIKE :term OR mini_profile_subtitle ILIKE :term OR mini_profile_tag_line ILIKE :term OR mini_profile_description ILIKE :term OR mini_profile_pronouns ILIKE :term
    OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(labels) AS label_val WHERE label_val ILIKE :term)
  SQL

  def show
    @query = params[:q].to_s.strip

    if @query.present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      @groups = Current.user.groups.where(GROUP_CONDITIONS, term: term).order_by_name_and_labels.to_a
      @profiles = Current.user.profiles.where(PROFILE_CONDITIONS, term: term).order_by_name_and_labels.to_a
    else
      @groups = []
      @profiles = []
    end
  end
end
