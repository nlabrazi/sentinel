require 'rails_helper'

RSpec.describe "Authentication", type: :request do
  describe "GET /users/sign_in" do
    it "renders a username login field instead of an email field" do
      get new_user_session_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Identifiant")
      expect(response.body).to include('name="user[username]"')
      expect(response.body).not_to include('name="user[email]"')
    end
  end

  describe "POST /users/sign_in" do
    it "signs in with a username and password" do
      user = create(:user, username: "admin", password: "password123456", password_confirmation: "password123456")

      post user_session_path, params: {
        user: {
          username: user.username,
          password: "password123456"
        }
      }

      expect(response).to redirect_to(root_path)
    end

    it "renders the Authentik SSO button and local login options" do
      get new_user_session_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Se connecter avec Authentik")
      expect(response.body).to include("ou compte local")
      expect(response.body).to include("Identifiant")
    end

    it "locks the account after maximum failed attempts" do
      user = create(:user, username: "admin", password: "password123456", password_confirmation: "password123456")

      5.times do
        post user_session_path, params: {
          user: {
            username: user.username,
            password: "wrongpassword123"
          }
        }
      end

      expect(user.reload.access_locked?).to be true
    end
  end

  describe "OmniAuth OpenID Connect SSO" do
    before do
      OmniAuth.config.test_mode = true
    end

    after do
      OmniAuth.config.test_mode = false
      OmniAuth.config.mock_auth[:openid_connect] = nil
    end

    it "authenticates an existing user and links provider credentials" do
      user = create(:user, email: "admin@sentinel.local", username: "admin")

      OmniAuth.config.mock_auth[:openid_connect] = OmniAuth::AuthHash.new(
        provider: "openid_connect",
        uid: "authentik-sub-12345",
        info: {
          email: "admin@sentinel.local",
          preferred_username: "admin"
        }
      )

      get user_openid_connect_omniauth_callback_path

      expect(response).to redirect_to(root_path)
      expect(user.reload.provider).to eq("openid_connect")
      expect(user.uid).to eq("authentik-sub-12345")
    end

    it "unlocks a locked user upon successful SSO authentication" do
      user = create(:user, email: "admin@sentinel.local", username: "admin")
      user.lock_access!
      expect(user.access_locked?).to be true

      OmniAuth.config.mock_auth[:openid_connect] = OmniAuth::AuthHash.new(
        provider: "openid_connect",
        uid: "authentik-sub-12345",
        info: {
          email: "admin@sentinel.local",
          preferred_username: "admin"
        }
      )

      get user_openid_connect_omniauth_callback_path

      expect(response).to redirect_to(root_path)
      expect(user.reload.access_locked?).to be false
    end
  end
end
