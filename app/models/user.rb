class User < ApplicationRecord
  # Users are created from the console or seeds only; no public registration route.
  # Other modules available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :rememberable, :validatable, :lockable,
         :omniauthable, omniauth_providers: [ :openid_connect ]

  validates :username,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: /\A[a-zA-Z0-9_.-]+\z/ }

  def self.from_omniauth(auth)
    # 1. Look up by existing provider + uid
    user = find_by(provider: auth.provider.to_s, uid: auth.uid.to_s)
    return user if user

    # 2. Look up by email (case-insensitive) to link existing local admin
    email = auth.info&.email&.downcase&.strip
    user = find_by("LOWER(email) = ?", email) if email.present?

    # 3. Look up by username (case-insensitive)
    preferred_username = (auth.info&.preferred_username || auth.info&.nickname || auth.info&.name)&.to_s&.strip
    if user.nil? && preferred_username.present?
      user = find_by("LOWER(username) = ?", preferred_username.downcase)
    end

    if user
      user.update!(
        provider: auth.provider.to_s,
        uid: auth.uid.to_s
      )
      user
    else
      # Provision new account if user does not exist yet
      fallback_name = preferred_username.presence || email&.split("@")&.first || "user"
      cleaned = fallback_name.gsub(/[^a-zA-Z0-9_.-]/, "")
      cleaned = "user" if cleaned.blank?

      candidate_username = cleaned
      counter = 1
      while User.exists?(username: candidate_username)
        candidate_username = "#{cleaned}#{counter}"
        counter += 1
      end

      create!(
        provider: auth.provider.to_s,
        uid: auth.uid.to_s,
        email: email.presence || "#{candidate_username}@sentinel.local",
        username: candidate_username,
        password: Devise.friendly_token[0, 32]
      )
    end
  end
end
