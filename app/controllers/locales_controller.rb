class LocalesController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  def update
    requested_locale = params[:locale].to_s.downcase

    target_locale = if I18n.available_locales.map(&:to_s).include?(requested_locale)
                      requested_locale
    else
                      I18n.default_locale.to_s
    end

    session[:locale] = target_locale
    cookies.permanent[:locale] = {
      value: target_locale,
      httponly: true,
      same_site: :lax
    }
    I18n.locale = target_locale.to_sym

    redirect_back fallback_location: root_path
  end
end
