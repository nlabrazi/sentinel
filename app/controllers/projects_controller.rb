class ProjectsController < ApplicationController
  before_action :set_project, only: [
    :show,
    :deploy,
    :refresh_screenshot,
    :refresh_github_commits,
    :toggle_maintenance
  ]

  def show
    @page_title = @project.name
    @compact_sidebar = true
    @deployments = @project.deployments.order(created_at: :desc).limit(20)
    @cron_jobs = @project.cron_jobs.includes(:job_executions).order(:name)
    @github_commits = @project.github_commits.order(committed_at: :desc, created_at: :desc).limit(20)
    @running_deployment = @project.deployments.running.order(created_at: :desc).first
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
    synced_count = GithubCommitsSyncService.new(@project).call

    redirect_to @project, notice: "#{synced_count} commit(s) synchronisé(s) depuis GitHub."
  rescue StandardError => e
    Rails.logger.error "GitHub commits refresh failed for #{@project.slug}: #{e.message}"
    redirect_to @project, alert: "Synchronisation GitHub impossible pour le moment."
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end
end
