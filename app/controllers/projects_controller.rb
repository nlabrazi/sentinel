class ProjectsController < ApplicationController
  before_action :set_project, only: [ :show, :deploy, :refresh_screenshot, :toggle_maintenance ]

  def show
    @page_title = @project.name
    @deployments = @project.deployments.order(created_at: :desc).limit(20)
  end

  def deploy
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

  private

  def set_project
    @project = Project.find(params[:id])
  end
end
