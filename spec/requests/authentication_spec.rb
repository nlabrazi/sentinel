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
end
