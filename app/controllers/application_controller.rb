class ApplicationController < ActionController::Base
  before_action :set_locale
  before_action :authenticate_user!, unless: :devise_controller?
  before_action :set_project_count, if: :user_signed_in?

  helper_method :current_locale

  layout :layout_by_resource

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def set_locale
    I18n.locale = extract_locale || I18n.default_locale
  end

  def extract_locale
    candidate = params[:locale] || session[:locale] || cookies[:locale]
    return nil if candidate.blank?

    candidate = candidate.to_s.downcase
    if I18n.available_locales.map(&:to_s).include?(candidate)
      session[:locale] = candidate
      cookies.permanent[:locale] = {
        value: candidate,
        httponly: true,
        same_site: :lax
      }
      candidate.to_sym
    end
  end

  def current_locale
    I18n.locale
  end

  def layout_by_resource
    devise_controller? ? "auth" : "application"
  end

  def set_project_count
    @project_count = Project.count
  end
end
