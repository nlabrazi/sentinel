FactoryBot.define do
  factory :user do
    sequence(:username) { |n| "admin-#{n}" }
    sequence(:email) { |n| "admin-#{n}@example.com" }
    password { "password123" }
    password_confirmation { password }
  end
end
