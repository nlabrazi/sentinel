class CronJob < ApplicationRecord
  belongs_to :project
  has_many :job_executions, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :project_id }
  validates :command, :schedule, presence: true
end
