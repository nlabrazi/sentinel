class DeployProjectJob < ApplicationJob
  queue_as :default

  def perform(project_id)
    project = Project.find(project_id)
    DeployProjectService.new(project).call
  end
end
