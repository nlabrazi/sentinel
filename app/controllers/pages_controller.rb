class PagesController < ApplicationController
  def deploys
    @page_title = "Deployments"
    @projects = Project.order(:name)
    @running_deployments = Deployment.includes(:project).where(status: :running).order(created_at: :desc)

    scope = filtered_deployments_scope

    @total_count = scope.count
    @limit = (params[:limit].presence || 20).to_i.clamp(10, 100)
    @deployments = scope.limit(@limit)

    calculate_deployment_stats
  end

  def settings
    @page_title = "Settings"
    @settings_summary = settings_summary
    @settings_sections = settings_sections
    @solid_queue_summary = solid_queue_summary
    @system_metrics = system_metrics
  end

  def trigger_healthcheck_all
    HealthcheckAllJob.perform_later
    redirect_to settings_path, notice: "Healthcheck global déclenché pour tous les projets."
  end

  def trigger_sync_github_all
    SyncGithubJob.perform_later
    redirect_to settings_path, notice: "Synchronisation GitHub déclenchée pour tous les projets."
  end

  def trigger_sync_cron_all
    CronStatusJob.perform_later
    redirect_to settings_path, notice: "Synchronisation des statuts cron déclenchée pour tous les projets."
  end

  def documentation
    @page_title = "Documentation"
  end

  private

  def settings_summary
    {
      app_name: "Sentinel",
      environment: Rails.env.capitalize,
      project_count: Project.count,
      created_at: Project.minimum(:created_at)
    }
  end

  def settings_sections
    {
      application_information: [
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

  def filtered_deployments_scope
    scope = Deployment.includes(:project).order(created_at: :desc)
    scope = scope.where(project_id: params[:project_id]) if params[:project_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present? && Deployment.statuses.key?(params[:status])

    if params[:q].present?
      query = "%#{Deployment.sanitize_sql_like(params[:q].to_s.strip)}%"
      scope = scope.joins(:project).where(
        "deployments.commit_sha ILIKE :query OR projects.name ILIKE :query",
        query: query
      )
    end

    scope
  end

  def calculate_deployment_stats
    @total_deployments_count = Deployment.count
    @success_deployments_count = Deployment.where(status: :success).count
    @failed_deployments_count = Deployment.where(status: :failed).count
    finished_count = @success_deployments_count + @failed_deployments_count
    @success_rate = finished_count.positive? ? ((@success_deployments_count.to_f / finished_count) * 100).round(1) : 0
    @avg_duration = Deployment.where(status: :success).where.not(duration: nil).average(:duration)&.round || 0
  end

  def solid_queue_summary
    active_processes = SolidQueue::Process.where("last_heartbeat_at >= ?", 5.minutes.ago).count
    failed_executions = SolidQueue::FailedExecution.count

    {
      active_processes: active_processes,
      failed_executions: failed_executions,
      recurring_tasks: [
        { name: "Healthcheck global", schedule: "every 1 minute", job: "HealthcheckAllJob" },
        { name: "Sync GitHub", schedule: "every 5 minutes", job: "SyncGithubJob" },
        { name: "Sync Cron", schedule: "every 5 minutes", job: "CronStatusJob" }
      ]
    }
  rescue StandardError => e
    Rails.logger.warn("Could not load SolidQueue summary: #{e.message}")
    { active_processes: 0, failed_executions: 0, recurring_tasks: [] }
  end

  def system_metrics
    {
      rails_version: Rails.version,
      ruby_version: RUBY_VERSION,
      database_adapter: ActiveRecord::Base.connection.adapter_name,
      active_storage_blobs_count: ActiveStorage::Blob.count,
      active_projects_count: Project.count,
      total_deployments_count: Deployment.count,
      total_cron_jobs_count: CronJob.count,
      current_username: current_user&.username || "admin"
    }
  rescue StandardError => e
    Rails.logger.warn("Could not load system metrics: #{e.message}")
    { rails_version: Rails.version, ruby_version: RUBY_VERSION }
  end
end
