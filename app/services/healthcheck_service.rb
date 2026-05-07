# Vérifie simplement que l'URL de production répond avec un code 2xx/3xx.
class HealthcheckService
  REQUEST_TIMEOUT_SECONDS = 5
  REDIRECT_LIMIT = 3
  USER_AGENT = "Sentinel Healthcheck"

  def initialize(project)
    @project = project
  end

  def call
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = HTTParty.get(
      @project.production_url,
      headers: { "User-Agent" => USER_AGENT },
      limit: REDIRECT_LIMIT,
      timeout: REQUEST_TIMEOUT_SECONDS
    )
    status = response.success? ? :online : :offline
    record_result!(
      status: status,
      http_status: response.code,
      response_time_ms: elapsed_ms(started_at)
    )
    status
  rescue HTTParty::Error, SocketError, SystemCallError, Timeout::Error => e
    Rails.logger.warn("Healthcheck failed for #{@project.slug}: #{e.class}: #{e.message}")
    record_result!(
      status: :offline,
      response_time_ms: elapsed_ms(started_at),
      error: "#{e.class}: #{e.message}".truncate(255)
    )
    :offline
  end

  private

  def record_result!(status:, http_status: nil, response_time_ms: nil, error: nil)
    @project.transaction do
      @project.update!(status: status)
      @project.pings.create!(
        status: status.to_s,
        http_status: http_status,
        response_time_ms: response_time_ms,
        error: error,
        checked_at: Time.current
      )
    end
  end

  def elapsed_ms(started_at)
    return nil unless started_at

    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
  end
end
