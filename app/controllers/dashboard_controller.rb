class DashboardController < ApplicationController
  def index
    @projects = Project.order(:name).to_a
    @latest_deployments_by_project_id = latest_deployments_by_project_id(@projects)
  end

  private

  def latest_deployments_by_project_id(projects)
    project_ids = projects.map(&:id)
    return {} if project_ids.empty?

    Deployment
      .where(project_id: project_ids)
      .select("DISTINCT ON (project_id) deployments.*")
      .order(:project_id, created_at: :desc)
      .index_by(&:project_id)
  end
end
