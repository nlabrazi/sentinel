require "fugit"

class CronJob < ApplicationRecord
  OVERDUE_GRACE = ENV.fetch("CRON_OVERDUE_GRACE_MINUTES", "15").to_i.minutes

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
    !%w[success failed].include?(last_status) || cron_schedule.nil?
  end

  def never_run?
    last_execution_at.blank?
  end

  def overdue?(at: Time.current)
    return false if never_run?

    cron = cron_schedule
    return false unless cron

    # Fugit searches strictly before its argument; include the cutoff second.
    cutoff = (at - OVERDUE_GRACE).utc
    expected_at = cron.previous_time(cutoff.floor + 1).to_t
    last_execution_at < expected_at
  rescue ArgumentError, RuntimeError
    # Invalid or impossible schedules must not interrupt monitoring.
    false
  end

  def needs_attention?(at: Time.current)
    failed? || overdue?(at: at) || never_run? || unknown?
  end

  def display_status
    return "failed" if failed?
    return "overdue" if overdue?
    return "never run" if never_run?
    return "unknown" if unknown?
    return "success" if success?

    "unknown"
  end

  def display_duration
    return "unknown" if last_duration.blank?

    "#{last_duration}s"
  end

  def last_log_excerpt(length: 140)
    latest_execution&.log.to_s.squish.truncate(length)
  end

  private

  def cron_schedule
    Fugit::Cron.parse("#{schedule} UTC")
  end
end
