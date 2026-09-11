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
end
