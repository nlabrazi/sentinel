require 'rails_helper'

RSpec.describe DeployProjectJob, type: :job do
  it 'calls DeployProjectService with the specified project' do
    project = create(:project)
    service = instance_double(DeployProjectService, call: true)

    allow(DeployProjectService).to receive(:new).with(project).and_return(service)

    described_class.perform_now(project.id)

    expect(service).to have_received(:call)
  end
end
