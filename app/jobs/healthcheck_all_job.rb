class HealthcheckAllJob < ApplicationJob
  queue_as :default

  def perform
    Project.find_each do |project|
      HealthcheckService.new(project).call
    end
  end
end
