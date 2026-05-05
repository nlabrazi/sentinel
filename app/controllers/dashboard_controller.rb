class DashboardController < ApplicationController
  def index
    @page_title = "Projects"
    @project_search = params[:q].to_s.strip
    @projects = dashboard_projects.to_a
    @latest_deployments_by_project_id = latest_deployments_by_project_id(@projects)
    @screenshots_enabled = ENV["APIFLASH_ACCESS_KEY"].present?
  end

  private

  def dashboard_projects
    projects = Project.order(:name)
    return projects if @project_search.blank?

    query = "%#{Project.sanitize_sql_like(@project_search)}%"
    projects.where("name ILIKE :query OR production_url ILIKE :query", query: query)
  end

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
