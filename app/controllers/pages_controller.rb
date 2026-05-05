class PagesController < ApplicationController
  def deploys
    @deployments = Deployment.includes(:project).order(created_at: :desc).limit(20)
  end

  def settings
    @settings_summary = settings_summary
    @settings_sections = settings_sections
  end

  private

  def settings_summary
    {
      app_name: "Sentinel",
      environment: Rails.env.capitalize,
      project_count: Project.count,
      user_count: User.count,
      created_at: Project.minimum(:created_at)
    }
  end

  def settings_sections
    {
      team_information: [
        [ "Name", "Sentinel" ],
        [ "Environment", Rails.env.capitalize ],
        [ "Projects", Project.count ],
        [ "Deployments", Deployment.count ],
        [ "Active Storage", Rails.application.config.active_storage.service.to_s ]
      ],
      environment_variables: [
        [ "GitHub token", configured?(ENV["GITHUB_TOKEN"]) ],
        [ "ApiFlash screenshots", configured?(ENV["APIFLASH_ACCESS_KEY"]) ],
        [ "VPS host", value_or_missing(ENV["VPS_HOST"]) ],
        [ "VPS user", value_or_missing(ENV["VPS_USER"]) ],
        [ "SSH key path", value_or_missing(ENV["SSH_KEY_PATH"]) ],
        [ "SSH connect timeout", "#{SshExecutionService::CONNECT_TIMEOUT_SECONDS}s" ],
        [ "SSH command timeout", "#{SshExecutionService::COMMAND_TIMEOUT_SECONDS}s" ]
      ],
      access_security: [
        [ "Authentication", "Devise sessions" ],
        [ "Public registration", "Disabled" ],
        [ "CI checks", "RSpec, RuboCop, bundler-audit, importmap audit, Brakeman" ],
        [ "Browser policy", "Modern browsers only" ]
      ]
    }
  end

  def configured?(value)
    value.present? ? "Configured" : "Missing"
  end

  def value_or_missing(value)
    value.present? ? value : "Missing"
  end
end
