class CronStatusSyncService
  MAX_LOG_BYTES = 16.kilobytes
  TRUNCATED_LOG_NOTICE = "\n\n[Log truncated]\n"
  SUCCESS_STATUSES = %w[success ok passed].freeze
  FAILED_STATUSES = %w[failed fail failure error].freeze

  def initialize(project)
    @project = project
  end

  def call
    result = SshExecutionService.new(@project).execute(@project.cron_status_command)
    return false unless result[:exit_code].zero?

    sync_payload(JSON.parse(result[:stdout]))
    true
  rescue JSON::ParserError => e
    Rails.logger.error "Cron status JSON invalid for #{@project.slug}: #{e.message}"
    false
  end

  private

  def sync_payload(payload)
    cron_job_payloads(payload).each do |attrs|
      sync_cron_job(attrs)
    end
  end

  def sync_cron_job(attrs)
    name = attrs["name"].to_s.strip
    return if name.blank?

    cron_job = @project.cron_jobs.find_or_initialize_by(name: name)
    executed_at = parse_time(attrs["last_execution_at"] || attrs["last_run"])
    status = normalize_status(attrs["last_status"] || attrs["status"])
    duration = attrs["last_duration"] || attrs["duration"]
    log = attrs["last_log"] || attrs["log"]

    cron_job.update!(
      command: attrs["command"].presence || cron_job.command.presence || "unknown",
      schedule: attrs["schedule"].presence || cron_job.schedule.presence || "unknown",
      last_execution_at: executed_at,
      last_status: status,
      last_duration: duration
    )

    create_execution_if_new(cron_job, executed_at, status, duration, log)
  end

  def create_execution_if_new(cron_job, executed_at, status, duration, log)
    return unless executed_at && JobExecution.validators_on(:status).first.options[:in].include?(status)
    return if cron_job.job_executions.exists?(executed_at: executed_at)

    cron_job.job_executions.create!(
      executed_at: executed_at,
      status: status,
      duration: duration,
      log: truncate_log(log.to_s)
    )
  end

  def cron_job_payloads(payload)
    if payload.is_a?(Hash) && payload["cron_jobs"].is_a?(Array)
      payload["cron_jobs"]
    elsif payload.is_a?(Hash)
      legacy_cron_job_payloads(payload)
    else
      []
    end
  end

  def legacy_cron_job_payloads(payload)
    payload.map do |job_name, attrs|
      next unless attrs.is_a?(Hash)

      attrs.merge("name" => job_name)
    end.compact
  end

  def normalize_status(value)
    status = value.to_s.downcase.strip
    return "success" if SUCCESS_STATUSES.include?(status)
    return "failed" if FAILED_STATUSES.include?(status)

    status.presence || "unknown"
  end

  def parse_time(value)
    return if value.blank?

    Time.zone.parse(value)
  rescue ArgumentError, TypeError
    nil
  end

  def truncate_log(log)
    return log if log.bytesize <= MAX_LOG_BYTES

    log.byteslice(0, MAX_LOG_BYTES - TRUNCATED_LOG_NOTICE.bytesize) + TRUNCATED_LOG_NOTICE
  end
end
