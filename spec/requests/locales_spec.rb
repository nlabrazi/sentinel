require 'rails_helper'

RSpec.describe 'Locales', type: :request do
  describe 'GET /locale/:locale' do
    it 'switches locale to English and redirects back' do
      get switch_locale_path(locale: :en), headers: { 'HTTP_REFERER' => root_path }

      expect(response).to redirect_to(root_path)
      expect(session[:locale]).to eq('en')
      expect(cookies[:locale]).to eq('en')
    end

    it 'switches locale to French and redirects back' do
      get switch_locale_path(locale: :fr), headers: { 'HTTP_REFERER' => root_path }

      expect(response).to redirect_to(root_path)
      expect(session[:locale]).to eq('fr')
      expect(cookies[:locale]).to eq('fr')
    end

    it 'falls back to root_path when HTTP_REFERER is not present' do
      get switch_locale_path(locale: :en)

      expect(response).to redirect_to(root_path)
    end

    it 'falls back to default locale when given an invalid locale' do
      get switch_locale_path(locale: :es), headers: { 'HTTP_REFERER' => root_path }

      expect(response).to redirect_to(root_path)
      expect(session[:locale]).to eq('fr')
      expect(cookies[:locale]).to eq('fr')
    end

    it 'persists selected locale across subsequent requests' do
      user = create(:user)
      sign_in user

      # Switch to English
      get switch_locale_path(locale: :en), headers: { 'HTTP_REFERER' => root_path }
      expect(response).to redirect_to(root_path)

      # Next request should use English from session/cookie
      get root_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Projects cockpit')
      expect(response.body).to include('Deployments')
      expect(response.body).to include('Settings')

      # Switch back to French
      get switch_locale_path(locale: :fr), headers: { 'HTTP_REFERER' => root_path }
      expect(response).to redirect_to(root_path)

      # Next request should use French
      get root_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Cockpit des projets')
      expect(response.body).to include('Déploiements')
      expect(response.body).to include('Paramètres')
    end
  end

  describe 'POST /locale/:locale' do
    it 'accepts POST method for switching locale' do
      post switch_locale_path(locale: :en), headers: { 'HTTP_REFERER' => settings_path }

      expect(response).to redirect_to(settings_path)
      expect(session[:locale]).to eq('en')
    end
  end

  describe 'Locale switcher UI' do
    it 'renders the language switcher with French and English flags in the navbar' do
      sign_in create(:user)

      get root_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include('/locale/fr')
      expect(response.body).to include('/locale/en')
      expect(response.body).to include('FR')
      expect(response.body).to include('EN')
    end
  end
end
