class CronJob < ApplicationRecord
  belongs_to :project
  has_many :job_executions, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :project_id }
  validates :command, :schedule, presence: true

  def latest_execution
    if job_executions.loaded?
      job_executions.max_by { |execution| execution.executed_at || execution.created_at }
    else
      job_executions.order(executed_at: :desc, created_at: :desc).first
    end
  end

  def success?
    last_status == "success"
  end

  def failed?
    last_status == "failed"
  end

  def unknown?
    last_status.blank? || last_status == "unknown"
  end

  def never_run?
    last_execution_at.blank?
  end

  def needs_attention?
    failed? || never_run? || unknown?
  end

  def display_status
    return "never run" if never_run?
    return "success" if success?
    return "failed" if failed?

    "unknown"
  end

  def display_duration
    return "unknown" if last_duration.blank?

    "#{last_duration}s"
  end

  def last_log_excerpt(length: 140)
    latest_execution&.log.to_s.squish.truncate(length)
  end
end
