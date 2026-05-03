class JobExecution < ApplicationRecord
  belongs_to :cron_job
end
