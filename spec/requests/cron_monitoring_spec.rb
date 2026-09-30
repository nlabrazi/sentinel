require "rails_helper"

RSpec.describe "Cron monitoring UI", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.utc(2026, 9, 30, 6, 30) }
  let(:project) { create(:project, cron_monitoring_enabled: true, cron_synced_at: now) }

  around { |example| travel_to(now) { example.run } }

  before do
    sign_in create(:user)
    stub_const("CronJob::OVERDUE_GRACE", 15.minutes)
    stub_const("Project::CRON_SYNC_STALE_AFTER", 15.minutes)
  end

  it "renders an overdue warning in both locales without an all-passing badge" do
    create(:cron_job, project: project, last_execution_at: now - 1.day)

    { fr: "En retard", en: "Overdue" }.each do |locale, label|
      get project_path(project), params: { locale: locale }
      expect(response).to have_http_status(:ok)
      section = Nokogiri::HTML(response.body).at_css("#cron-jobs")
      expect(section.text).to include(label)
      expect(section.text).not_to include("All passing")
      status = section.at_css("tbody tr td:nth-child(4)")
      expect(status.text).to include(label)
      expect(status.inner_html).not_to include("bg-green")

      get root_path, params: { locale: locale }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(label)
    end
  end

  it "renders stale sync independently of successful job executions" do
    project.update!(cron_synced_at: now - 1.hour)
    create(:cron_job, project: project)

    { fr: "Synchronisation cron ancienne ou absente", en: "Cron sync stale or missing" }.each do |locale, label|
      get project_path(project), params: { locale: locale }
      section = Nokogiri::HTML(response.body).at_css("#cron-jobs")
      expect(section.text).to include(label)
      expect(section.at_css("tbody").text).to include("success")
    end
  end
end
