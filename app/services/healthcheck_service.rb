# Vérifie simplement que l'URL de production répond avec un code 2xx/3xx.
class HealthcheckService
  REQUEST_TIMEOUT_SECONDS = 5
  REDIRECT_LIMIT = 3
  USER_AGENT = "Sentinel Healthcheck"

  def initialize(project)
    @project = project
  end

  def call
    response = HTTParty.get(
      @project.production_url,
      headers: { "User-Agent" => USER_AGENT },
      limit: REDIRECT_LIMIT,
      timeout: REQUEST_TIMEOUT_SECONDS
    )
    status = response.success? ? :online : :offline
    @project.update!(status: status)
    status
  rescue HTTParty::Error, SocketError, SystemCallError, Timeout::Error => e
    Rails.logger.warn("Healthcheck failed for #{@project.slug}: #{e.class}: #{e.message}")
    @project.update!(status: :offline)
    :offline
  end
end
