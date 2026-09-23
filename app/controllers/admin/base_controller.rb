# Site-wide admin pages. Signed-in admins only.
class Admin::BaseController < ApplicationController
  include OurSidebar
  before_action :require_admin
end
