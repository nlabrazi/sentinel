class ProjectsController < ApplicationController
  before_action :set_project, only: [
    :show,
    :deploy,
    :refresh_screenshot,
    :refresh_github_commits,
    :refresh_runtime,
    :toggle_maintenance
  ]

  def show
    @page_title = @project.name
    @compact_sidebar = true
    @deployments = @project.deployments.order(created_at: :desc).limit(20)
    @cron_jobs = @project.cron_jobs.includes(:job_executions).order(:name)
    @github_commits = @project.github_commits.order(committed_at: :desc, created_at: :desc).limit(20)
    @github_pull_requests = @project.github_pull_requests.order(github_updated_at: :desc, created_at: :desc).limit(20)
    @running_deployment = @project.deployments.running.order(created_at: :desc).first
    @latest_ping = @project.latest_ping
  end

  def deploy
    if @project.deployments.running.exists?
      redirect_to @project, alert: "Un déploiement est déjà en cours pour ce projet."
      return
    end

    DeployProjectJob.perform_later(@project.id)
    redirect_to @project, notice: "Déploiement lancé en arrière-plan."
  end

  def toggle_maintenance
    new_mode = !@project.maintenance_mode?

    begin
      ssh = SshExecutionService.new(@project)
      result = ssh.execute(@project.maintenance_command(new_mode))

      if result[:exit_code].zero?
        @project.update!(maintenance_mode: new_mode)
        redirect_to @project, notice: "Mode maintenance #{new_mode ? 'activé' : 'désactivé'}."
      else
        flash[:alert] = "Erreur SSH : #{result[:stderr]}"
        redirect_to @project
      end
    rescue StandardError => e
      flash[:alert] = "Erreur lors du basculement : #{e.message}"
      redirect_to @project
    end
  end

  def refresh_screenshot
    @project.regenerate_screenshot!(force: true)
    redirect_to @project, notice: "Aperçu mis à jour."
  end

  def refresh_github_commits
    synced_commits_count = GithubCommitsSyncService.new(@project).call
    synced_pull_requests_count = GithubPullRequestsSyncService.new(@project).call
    @project.update!(github_synced_at: Time.current)

    redirect_back fallback_location: @project,
                notice: "#{synced_commits_count} commit(s) et #{synced_pull_requests_count} pull request(s) synchronisé(s) depuis GitHub."
  rescue StandardError => e
    Rails.logger.error "GitHub refresh failed for #{@project.slug}: #{e.message}"
    redirect_back fallback_location: @project, alert: "Synchronisation GitHub impossible pour le moment."
  end

  def refresh_runtime
    status = HealthcheckService.new(@project).call

    redirect_back fallback_location: @project, notice: "Healthcheck terminé : #{status}."
  rescue StandardError => e
    Rails.logger.error "Runtime refresh failed for #{@project.slug}: #{e.message}"
    redirect_back fallback_location: @project, alert: "Healthcheck impossible pour le moment."
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end
end
