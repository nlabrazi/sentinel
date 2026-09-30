require "rails_helper"

RSpec.describe "Cron metrics", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.utc(2026, 9, 30, 6, 30) }
  let(:token) { "test-metrics-token" }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }
  let(:project) { create(:project, slug: "sawt-ai", cron_monitoring_enabled: true, cron_synced_at: now) }

  around do |example|
    original_token = ENV["PROMETHEUS_METRICS_TOKEN"]
    ENV["PROMETHEUS_METRICS_TOKEN"] = token
    travel_to(now) { example.run }
  ensure
    ENV["PROMETHEUS_METRICS_TOKEN"] = original_token
  end

  before do
    stub_const("CronJob::OVERDUE_GRACE", 15.minutes)
    stub_const("Project::CRON_SYNC_STALE_AFTER", 15.minutes)
  end

  it "returns Prometheus text without a Devise session or cookies" do
    get metrics_path, headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to eq("text/plain; version=0.0.4; charset=utf-8")
    expect(response.headers["Cache-Control"]).to eq("no-store")
    expect(response.headers["Set-Cookie"]).to be_nil
    expect(response.body).to include("# HELP sentinel_cron_job_healthy ", "# TYPE sentinel_cron_job_healthy gauge\n")
    expect(response.body).to end_with("\n")
  end

  it "rejects missing, incorrect, and non-Bearer credentials before querying projects" do
    expect(Project).not_to receive(:where)

    [ nil, "Bearer wrong", "Basic #{token}", "Bearer ", "Bearer #{token} extra" ].each do |authorization|
      get metrics_path, headers: { "Authorization" => authorization }
      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["Location"]).to be_nil
      expect(response.body).not_to include("sentinel_cron_")
    end
  end

  it "rejects requests when the server token is unconfigured" do
    [ nil, "", " " ].each do |value|
      ENV["PROMETHEUS_METRICS_TOKEN"] = value
      get metrics_path, headers: headers
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it "does not accept a token in the URL or a Devise session as authorization" do
    sign_in create(:user)
    get metrics_path, params: { token: token }
    expect(response).to have_http_status(:unauthorized)
  end

  it "filters the authorization header from the Rails request environment" do
    get metrics_path, headers: headers
    expect(request.filtered_env["HTTP_AUTHORIZATION"]).to eq("[FILTERED]")
    expect(response.body).not_to include(token)
  end

  it "exports healthy jobs, execution timestamps, duration, and recent project sync" do
    create(:cron_job, project: project, name: "keepalive", last_execution_at: now - 1.minute, last_duration: 0)
    get metrics_path, headers: headers

    expect_metric("job_healthy", 1, job: "keepalive")
    expect_metric("job_failed", 0, job: "keepalive")
    expect_metric("job_overdue", 0, job: "keepalive")
    expect_metric("job_last_execution_timestamp_seconds", (now - 1.minute).to_i, job: "keepalive")
    expect_metric("job_last_duration_seconds", 0, job: "keepalive")
    expect_metric("project_last_sync_timestamp_seconds", now.to_i)
    expect_metric("project_sync_stale", 0)
    expect_metric("project_healthy", 1)
  end

  it "exports failed and overdue flags independently" do
    create(:cron_job, project: project, name: "failed", last_status: "failed")
    create(:cron_job, project: project, name: "late", schedule: "15 0,6,12,18 * * *", last_execution_at: now - 6.hours - 15.minutes)
    get metrics_path, headers: headers

    expect_metric("job_healthy", 0, job: "failed")
    expect_metric("job_failed", 1, job: "failed")
    expect_metric("job_overdue", 0, job: "failed")
    expect_metric("job_healthy", 0, job: "late")
    expect_metric("job_failed", 0, job: "late")
    expect_metric("job_overdue", 1, job: "late")
    expect_metric("project_healthy", 0)
  end

  it "exports never-run and unknown jobs as unhealthy and omits unavailable measurements" do
    create(:cron_job, project: project, name: "never", last_execution_at: nil, last_duration: nil)
    create(:cron_job, project: project, name: "unknown", last_status: "unknown")
    create(:cron_job, project: project, name: "invalid", schedule: "invalid")
    get metrics_path, headers: headers

    %w[never unknown invalid].each do |job|
      expect_metric("job_healthy", 0, job: job)
      expect_metric("job_overdue", 0, job: job)
    end
    expect(response.body).not_to include('sentinel_cron_job_last_execution_timestamp_seconds{project="sawt-ai",job="never"}')
    expect(response.body).not_to include('sentinel_cron_job_last_duration_seconds{project="sawt-ai",job="never"}')
  end

  it "reports stale sync even with healthy executions" do
    project.update!(cron_synced_at: now - 15.minutes)
    create(:cron_job, project: project, name: "healthy")
    get metrics_path, headers: headers

    expect_metric("job_healthy", 1, job: "healthy")
    expect_metric("project_sync_stale", 1)
    expect_metric("project_healthy", 0)
    expect_metric("project_last_sync_timestamp_seconds", (now - 15.minutes).to_i)
  end

  it "reports missing sync and no reported jobs as unhealthy" do
    project.update!(cron_synced_at: nil)
    get metrics_path, headers: headers

    expect_metric("project_sync_stale", 1)
    expect_metric("project_healthy", 0)
    expect(response.body).not_to include('sentinel_cron_project_last_sync_timestamp_seconds{project="sawt-ai"}')
    expect(response.body).not_to include('sentinel_cron_job_healthy{')

    project.update!(cron_synced_at: now)
    get metrics_path, headers: headers
    expect_metric("project_sync_stale", 0)
    expect_metric("project_healthy", 0)
  end

  it "excludes disabled projects and their jobs" do
    project.update!(cron_monitoring_enabled: false)
    create(:cron_job, project: project)
    get metrics_path, headers: headers
    expect(response.body).not_to include('project="sawt-ai"')
  end

  it "escapes quotes, backslashes, and newlines without introducing extra labels or samples" do
    create(:cron_job, project: project, name: "job\\name\"\nnext", command: "secret command")
    get metrics_path, headers: headers

    escaped = 'job\\\\name\"\nnext'
    expect_metric("job_healthy", 1, job: escaped)
    samples = response.body.lines.reject { |line| line.start_with?("#") }
    expect(samples.size).to eq(8)
    expect(response.body).not_to include("secret command", "schedule=", "command=", "log=")
  end

  def expect_metric(suffix, value, job: nil)
    labels = 'project="sawt-ai"'
    labels += %(,job="#{job}") if job
    expect(response.body.lines).to include("sentinel_cron_#{suffix}{#{labels}} #{value}\n")
  end
end
