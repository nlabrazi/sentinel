class User < ApplicationRecord
  # Users are created from the console or seeds only; no public registration route.
  # Other modules available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :rememberable, :validatable
end
