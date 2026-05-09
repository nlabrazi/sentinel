class CronStatusSyncService
  MAX_LOG_BYTES = 16.kilobytes
  TRUNCATED_LOG_NOTICE = "\n\n[Log truncated]\n"

  SUPPORTED_VERSION = 1

  SUCCESS_STATUSES = %w[success ok passed].freeze
  FAILED_STATUSES = %w[failed fail failure error].freeze
  UNKNOWN_STATUSES = %w[unknown skipped pending].freeze

  VALID_STATUSES = %w[success failed unknown].freeze

  def initialize(project)
    @project = project
  end

  def call
    result = SshExecutionService.new(@project).execute(@project.cron_status_command)

    unless result[:exit_code].zero?
      Rails.logger.error(
        "Cron status command failed for #{@project.slug}: " \
        "exit_code=#{result[:exit_code]} stderr=#{result[:stderr].to_s.squish}"
      )

      return false
    end

    payload = JSON.parse(result[:stdout].to_s)
    sync_payload(payload)

    @project.update!(cron_synced_at: Time.current)

    true
  rescue JSON::ParserError => e
    Rails.logger.error "Cron status JSON invalid for #{@project.slug}: #{e.message}"
    false
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Cron status sync invalid for #{@project.slug}: #{e.record.errors.full_messages.join(', ')}"
    false
  rescue StandardError => e
    Rails.logger.error "Cron status sync failed for #{@project.slug}: #{e.class}: #{e.message}"
    false
  end

  private

  def sync_payload(payload)
    unless payload.is_a?(Hash)
      Rails.logger.warn "Cron status payload ignored for #{@project.slug}: root must be a JSON object"
      return
    end

    validate_payload_version(payload)

    jobs = cron_job_payloads(payload)

    if jobs.empty?
      Rails.logger.info "Cron status payload for #{@project.slug} contains no jobs"
      return
    end

    jobs.each do |attrs|
      sync_cron_job(attrs)
    end
  end

  def validate_payload_version(payload)
    return unless payload.key?("version")

    version = payload["version"].to_i

    return if version == SUPPORTED_VERSION

    Rails.logger.warn(
      "Cron status payload version mismatch for #{@project.slug}: " \
      "expected=#{SUPPORTED_VERSION} received=#{payload['version']}"
    )
  end

  def sync_cron_job(attrs)
    unless attrs.is_a?(Hash)
      Rails.logger.warn "Cron job payload ignored for #{@project.slug}: job entry must be an object"
      return
    end

    name = attrs["name"].to_s.strip

    if name.blank?
      Rails.logger.warn "Cron job payload ignored for #{@project.slug}: missing name"
      return
    end

    cron_job = @project.cron_jobs.find_or_initialize_by(name: name)

    executed_at = parse_time(attrs["last_execution_at"] || attrs["last_run"])
    status = normalize_status(attrs["last_status"] || attrs["status"])
    duration = normalize_duration(attrs["last_duration"] || attrs["duration"])
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
    return unless executed_at.present?
    return unless VALID_STATUSES.include?(status)
    return if cron_job.job_executions.exists?(executed_at: executed_at)

    cron_job.job_executions.create!(
      executed_at: executed_at,
      status: status,
      duration: duration,
      log: truncate_log(log.to_s)
    )
  end

  def cron_job_payloads(payload)
    if payload["jobs"].is_a?(Array)
      payload["jobs"]
    elsif payload["cron_jobs"].is_a?(Array)
      Rails.logger.warn "Cron status payload for #{@project.slug} uses deprecated key cron_jobs; use jobs instead"
      payload["cron_jobs"]
    else
      legacy_cron_job_payloads(payload)
    end
  end

  def legacy_cron_job_payloads(payload)
    ignored_keys = %w[version generated_at jobs cron_jobs]

    payload.filter_map do |job_name, attrs|
      next if ignored_keys.include?(job_name)
      next unless attrs.is_a?(Hash)

      Rails.logger.warn "Cron status payload for #{@project.slug} uses legacy job map format"

      attrs.merge("name" => job_name)
    end
  end

  def normalize_status(value)
    status = value.to_s.downcase.strip

    return "success" if SUCCESS_STATUSES.include?(status)
    return "failed" if FAILED_STATUSES.include?(status)
    return "unknown" if UNKNOWN_STATUSES.include?(status)

    "unknown"
  end

  def normalize_duration(value)
    return if value.blank?

    Integer(value)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_time(value)
    return if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def truncate_log(log)
    return log if log.bytesize <= MAX_LOG_BYTES

    log.byteslice(0, MAX_LOG_BYTES - TRUNCATED_LOG_NOTICE.bytesize) + TRUNCATED_LOG_NOTICE
  end
end
