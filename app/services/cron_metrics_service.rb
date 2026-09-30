class CronMetricsService
  METRICS = {
    job_healthy: "Whether the cron job needs no attention (1 healthy, 0 unhealthy).",
    job_failed: "Whether the last execution failed.",
    job_overdue: "Whether an expected cron occurrence was missed beyond the grace period.",
    job_last_execution_timestamp_seconds: "Unix timestamp of the last cron execution; omitted if never run.",
    job_last_duration_seconds: "Duration of the last cron execution; omitted if unknown.",
    project_last_sync_timestamp_seconds: "Unix timestamp of the last successful cron sync; omitted if never synced.",
    project_sync_stale: "Whether the project cron sync is stale or missing.",
    project_healthy: "Whether the project has healthy cron jobs and a recent sync."
  }.freeze

  def initialize(at: Time.current)
    @at = at
  end

  def call
    samples = METRICS.keys.to_h { |key| [ key, [] ] }

    Project.where(cron_monitoring_enabled: true).includes(:cron_jobs).find_each do |project|
      labels = { project: project.slug }
      add(samples, :project_last_sync_timestamp_seconds, labels, project.cron_synced_at&.to_i)
      add(samples, :project_sync_stale, labels, project.cron_sync_stale?(at: @at) ? 1 : 0)
      add(samples, :project_healthy, labels, project.cron_needs_attention?(at: @at) ? 0 : 1)

      project.cron_jobs.each do |job|
        job_labels = labels.merge(job: job.name)
        add(samples, :job_healthy, job_labels, job.needs_attention?(at: @at) ? 0 : 1)
        add(samples, :job_failed, job_labels, job.failed? ? 1 : 0)
        add(samples, :job_overdue, job_labels, job.overdue?(at: @at) ? 1 : 0)
        add(samples, :job_last_execution_timestamp_seconds, job_labels, job.last_execution_at&.to_i)
        add(samples, :job_last_duration_seconds, job_labels, job.last_duration)
      end
    end

    METRICS.flat_map do |key, help|
      name = "sentinel_cron_#{key}"
      [ "# HELP #{name} #{help}", "# TYPE #{name} gauge", *samples.fetch(key) ]
    end.join("\n") + "\n"
  end

  private

  def add(samples, key, labels, value)
    return if value.nil?

    encoded_labels = labels.map { |name, label| %(#{name}="#{escape_label(label)}") }.join(",")
    samples.fetch(key) << "sentinel_cron_#{key}{#{encoded_labels}} #{value}"
  end

  def escape_label(value)
    value.to_s.gsub(/[\\"\n]/) { |character| { "\\" => "\\\\", '"' => '\\"', "\n" => '\\n' }.fetch(character) }
  end
end
