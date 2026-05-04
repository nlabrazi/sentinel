class DashboardController < ApplicationController
  def index
    @projects = Project.includes(:deployments).order(:name)
  end
end
