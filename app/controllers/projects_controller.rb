class ProjectsController < ApplicationController
  before_action :set_project, only: [:show, :deploy, :toggle_maintenance]

  def index
    @projects = Project.order(:name)
  end

  def show
  end

  def deploy
    DeployProjectJob.perform_later(@project.id)
    redirect_to @project, notice: "Déploiement lancé en arrière-plan."
  end

  def toggle_maintenance
    new_mode = !@project.maintenance_mode?
    @project.update!(maintenance_mode: new_mode)

    # Action SSH sécurisée – en cas d'échec on prévient sans planter
    begin
      ssh = SshExecutionService.new(@project)
      command = new_mode ? "touch #{@project.vps_path}/maintenance.on" : "rm -f #{@project.vps_path}/maintenance.on"
      result = ssh.execute(command)
      if result[:exit_code].zero?
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

  private

  def set_project
    @project = Project.find(params[:id])
  end
end
