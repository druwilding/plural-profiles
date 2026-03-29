module OurSidebar
  extend ActiveSupport::Concern

  included do
    before_action :set_sidebar_data
  end

  private

  def set_sidebar_data
    return unless authenticated?

    @sidebar_profiles = Current.user.profiles.order_by_name_and_labels
    @sidebar_groups = Current.user.groups.order_by_name_and_labels
  end
end
