module Our::GroupsHelper
  def grouped_theme_options(personal, shared)
    groups = []
    groups << [ "Our themes", personal.map { |t| [ t.name, t.id ] } ] if personal.any?
    groups << [ "Shared themes", shared.map { |t| [ t.name, t.id ] } ] if shared.any?
    groups
  end
end
