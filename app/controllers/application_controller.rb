class ApplicationController < ActionController::Base
  before_action :authenticate_user!, unless: :devise_controller?
  before_action :set_project_count, if: :user_signed_in?

  layout :layout_by_resource

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def layout_by_resource
    devise_controller? ? "auth" : "application"
  end

  def set_project_count
    @project_count = Project.count
  end
end
