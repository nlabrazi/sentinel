require 'rails_helper'

RSpec.describe "Dashboards", type: :request do
  describe "GET /" do
    it "redirects anonymous users to the login page" do
      get root_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "returns http success for authenticated users" do
      sign_in create(:user)

      get root_path
      expect(response).to have_http_status(:success)
    end
  end
end
