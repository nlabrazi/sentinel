class JobExecution < ApplicationRecord
  belongs_to :cron_job

  validates :status, inclusion: { in: %w[success failed] }
end
