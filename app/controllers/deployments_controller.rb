class DeploymentsController < ApplicationController
  def show
    @deployment = Deployment.includes(:project).find(params[:id])
    @project = @deployment.project
    @page_title = "Deployment #{@deployment.commit_sha.first(7)}"
  end
end
