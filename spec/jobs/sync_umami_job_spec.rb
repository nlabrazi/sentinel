# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncUmamiJob, type: :job do
  it "syncs eligible projects via ProjectUmamiSyncService" do
    first_project = create(:project, production_url: "https://first.example.com")
    second_project = create(:project, production_url: "https://second.example.com")

    allow(ProjectUmamiSyncService).to receive(:call).and_return(
      ProjectUmamiSyncService::Result.new(success?: true)
    )

    described_class.perform_now

    expect(ProjectUmamiSyncService).to have_received(:call).with(first_project)
    expect(ProjectUmamiSyncService).to have_received(:call).with(second_project)
  end

  it "syncs only the target project when project_id is provided" do
    target_project = create(:project, production_url: "https://target.example.com")
    other_project = create(:project, production_url: "https://other.example.com")

    allow(ProjectUmamiSyncService).to receive(:call).and_return(
      ProjectUmamiSyncService::Result.new(success?: true)
    )

    described_class.perform_now(target_project.id)

    expect(ProjectUmamiSyncService).to have_received(:call).with(target_project)
    expect(ProjectUmamiSyncService).not_to have_received(:call).with(other_project)
  end

  it "isolates errors per project and continues processing" do
    failing_project = create(:project, slug: "failing-app", production_url: "https://fail.example.com")
    healthy_project = create(:project, slug: "healthy-app", production_url: "https://healthy.example.com")

    allow(Rails.logger).to receive(:error)
    allow(ProjectUmamiSyncService).to receive(:call).with(failing_project).and_raise(StandardError, "API error")
    allow(ProjectUmamiSyncService).to receive(:call).with(healthy_project).and_return(
      ProjectUmamiSyncService::Result.new(success?: true)
    )

    described_class.perform_now

    expect(ProjectUmamiSyncService).to have_received(:call).with(healthy_project)
    expect(Rails.logger).to have_received(:error).with(/SyncUmamiJob failed for failing-app: API error/)
  end
end
