# frozen_string_literal: true

module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    skip_before_action :verify_authenticity_token, only: [ :openid_connect ]

    def openid_connect
      auth = request.env["omniauth.auth"]

      if auth.blank?
        redirect_to new_user_session_path, alert: "Échec de connexion : données d'authentification manquantes."
        return
      end

      @user = User.from_omniauth(auth)

      if @user&.persisted?
        @user.unlock_access! if @user.respond_to?(:unlock_access!) && @user.access_locked?

        sign_in_and_redirect @user, event: :authentication
        set_flash_message(:notice, :success, kind: "Authentik") if is_navigational_format?
      else
        redirect_to new_user_session_path, alert: (@user&.errors&.full_messages&.join(", ") || "Impossible de vous connecter via Authentik.")
      end
    end

    def failure
      redirect_to new_user_session_path, alert: "Échec de l'authentification Authentik (#{failure_message || 'erreur inconnue'})."
    end
  end
end
