# Vérifie simplement que l'URL de production répond avec un code 2xx/3xx.
class HealthcheckService
  def initialize(project)
    @project = project
  end

  def call
    response = HTTParty.get(@project.production_url, timeout: 5)
    status = response.success? ? :online : :offline
    @project.update!(status: status)
    status
  rescue StandardError
    @project.update!(status: :offline)
    :offline
  end
end
