class Deployment < ApplicationRecord
  belongs_to :project

  validates :commit_sha, presence: true

  enum :status, { pending: 0, running: 1, success: 2, failed: 3 }, prefix: true
end
