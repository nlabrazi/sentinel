class Ping < ApplicationRecord
  belongs_to :project

  validates :status, inclusion: { in: %w[online offline] }
  validates :checked_at, presence: true
  validates :http_status, numericality: { only_integer: true, allow_nil: true }
  validates :response_time_ms, numericality: { only_integer: true, greater_than_or_equal_to: 0, allow_nil: true }
end
