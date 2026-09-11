require 'rails_helper'

RSpec.describe User, type: :model do
  subject(:user) { build(:user) }

  it { is_expected.to validate_presence_of(:username) }
  it { is_expected.to validate_uniqueness_of(:username).case_insensitive }
  it { is_expected.to validate_presence_of(:email) }
  it { is_expected.to validate_uniqueness_of(:email).case_insensitive }

  it "is valid with a password of 12 characters or more" do
    expect(build(:user, password: "a" * 12, password_confirmation: "a" * 12)).to be_valid
  end

  it "is invalid with a password of less than 12 characters" do
    expect(build(:user, password: "a" * 11, password_confirmation: "a" * 11)).not_to be_valid
  end

  it "responds to lockable methods" do
    user = build(:user)
    expect(user).to respond_to(:failed_attempts)
    expect(user).to respond_to(:locked_at)
    expect(user).to respond_to(:lock_access!)
    expect(user).to respond_to(:unlock_access!)
  end

  describe ".from_omniauth" do
    let(:auth) do
      OmniAuth::AuthHash.new(
        provider: "openid_connect",
        uid: "auth-uid-12345",
        info: {
          email: "admin@example.com",
          preferred_username: "admin"
        }
      )
    end

    it "links Authentik SSO credentials to an existing user by email" do
      existing_user = create(:user, email: "admin@example.com", username: "localadmin")

      user = User.from_omniauth(auth)

      expect(user.id).to eq(existing_user.id)
      expect(user.provider).to eq("openid_connect")
      expect(user.uid).to eq("auth-uid-12345")
    end

    it "links Authentik SSO credentials to an existing user by username" do
      existing_user = create(:user, email: "other@example.com", username: "admin")

      user = User.from_omniauth(auth)

      expect(user.id).to eq(existing_user.id)
      expect(user.provider).to eq("openid_connect")
      expect(user.uid).to eq("auth-uid-12345")
    end

    it "returns the user if already linked by provider and uid" do
      linked_user = create(:user, provider: "openid_connect", uid: "auth-uid-12345")

      user = User.from_omniauth(auth)

      expect(user.id).to eq(linked_user.id)
    end

    it "provisions a new user if no match is found" do
      new_auth = OmniAuth::AuthHash.new(
        provider: "openid_connect",
        uid: "brand-new-user-999",
        info: {
          email: "newperson@example.com",
          preferred_username: "newperson"
        }
      )

      expect {
        user = User.from_omniauth(new_auth)
        expect(user).to be_persisted
        expect(user.email).to eq("newperson@example.com")
        expect(user.username).to eq("newperson")
        expect(user.provider).to eq("openid_connect")
        expect(user.uid).to eq("brand-new-user-999")
      }.to change(User, :count).by(1)
    end
  end
end
