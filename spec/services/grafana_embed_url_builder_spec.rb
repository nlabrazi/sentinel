require "rails_helper"
require "cgi"

RSpec.describe GrafanaEmbedUrlBuilder, type: :service do
  GRAFANA_ENV_KEYS = %w[
    GRAFANA_BASE_URL
    GRAFANA_DASHBOARD_UID
    GRAFANA_DASHBOARD_SLUG
    GRAFANA_VARIABLE_NAME
    GRAFANA_DEFAULT_THEME
    GRAFANA_ORG_ID
    GRAFANA_DEFAULT_FROM
    GRAFANA_DEFAULT_TO
    GRAFANA_DEFAULT_TIMEZONE
    GRAFANA_REFRESH
    GRAFANA_PANEL_ID
    GRAFANA_GLOBAL_VARIABLE_VALUE
  ].freeze

  around do |example|
    original_env = GRAFANA_ENV_KEYS.to_h { |key| [ key, ENV[key] ] }

    GRAFANA_ENV_KEYS.each { |key| ENV.delete(key) }
    example.run
  ensure
    GRAFANA_ENV_KEYS.each do |key|
      if original_env[key].nil?
        ENV.delete(key)
      else
        ENV[key] = original_env[key]
      end
    end
  end

  before do
    ENV["GRAFANA_BASE_URL"] = "https://grafana.example.com"
    ENV["GRAFANA_DASHBOARD_UID"] = "apps-overview"
    ENV["GRAFANA_DASHBOARD_SLUG"] = "applications-overview"
    ENV["GRAFANA_VARIABLE_NAME"] = "app"
    ENV["GRAFANA_DEFAULT_THEME"] = "dark"
    ENV["GRAFANA_ORG_ID"] = "1"
    ENV["GRAFANA_DEFAULT_FROM"] = "now-6h"
    ENV["GRAFANA_DEFAULT_TO"] = "now"
    ENV["GRAFANA_DEFAULT_TIMEZONE"] = "browser"
    ENV["GRAFANA_REFRESH"] = "30s"
    ENV["GRAFANA_GLOBAL_VARIABLE_VALUE"] = "All"
  end

  it "builds a project dashboard URL from the explicit Grafana app value" do
    project = build(:project, slug: "sentinel-slug", grafana_app_value: "prometheus-app-label")

    uri = URI.parse(described_class.call(project: project))

    expect(uri).to have_attributes(
      scheme: "https",
      host: "grafana.example.com",
      path: "/d/apps-overview/applications-overview"
    )
    expect(query_params(uri)).to include(
      "orgId" => [ "1" ],
      "from" => [ "now-6h" ],
      "to" => [ "now" ],
      "timezone" => [ "browser" ],
      "refresh" => [ "30s" ],
      "theme" => [ "dark" ],
      "var-app" => [ "prometheus-app-label" ]
    )
  end

  it "builds a global dashboard URL with the configured global variable value" do
    uri = URI.parse(described_class.call)

    expect(uri.path).to eq("/d/apps-overview/applications-overview")
    expect(query_params(uri)).to include("var-app" => [ "All" ])
  end

  it "builds a d-solo panel URL when a panel id is provided" do
    project = build(:project, grafana_app_value: "media-tools")

    uri = URI.parse(described_class.call(project: project, panel_id: 12))

    expect(uri.path).to eq("/d-solo/apps-overview/applications-overview")
    expect(query_params(uri)).to include(
      "panelId" => [ "12" ],
      "var-app" => [ "media-tools" ]
    )
  end

  it "builds a d-solo panel URL from the configured panel id" do
    ENV["GRAFANA_PANEL_ID"] = "panel-6"
    project = build(:project, grafana_app_value: "media-tools")

    uri = URI.parse(described_class.call(project: project))

    expect(uri.path).to eq("/d-solo/apps-overview/applications-overview")
    expect(query_params(uri)).to include(
      "panelId" => [ "panel-6" ],
      "var-app" => [ "media-tools" ]
    )
  end

  it "preserves a Grafana base path" do
    ENV["GRAFANA_BASE_URL"] = "https://observability.example.com/grafana"

    uri = URI.parse(described_class.call)

    expect(uri.path).to eq("/grafana/d/apps-overview/applications-overview")
  end

  it "encodes query values and supports per-call options" do
    project = build(:project, grafana_app_value: "media tools/prod")

    uri = URI.parse(
      described_class.call(
        project: project,
        from: "now-1h",
        to: "now",
        theme: "light",
        kiosk: true
      )
    )

    expect(query_params(uri)).to include(
      "from" => [ "now-1h" ],
      "to" => [ "now" ],
      "timezone" => [ "browser" ],
      "refresh" => [ "30s" ],
      "theme" => [ "light" ],
      "kiosk" => [],
      "var-app" => [ "media tools/prod" ]
    )
  end

  it "returns nil when a project has no Grafana mapping" do
    project = build(:project, grafana_app_value: nil)

    expect(described_class.call(project: project)).to be_nil
  end

  it "returns nil when required config is missing" do
    ENV.delete("GRAFANA_DASHBOARD_UID")

    expect(described_class.call).to be_nil
  end

  it "returns nil when the base URL contains credentials" do
    ENV["GRAFANA_BASE_URL"] = "https://user:password@grafana.example.com"

    expect(described_class.call).to be_nil
  end

  it "returns nil when the Grafana variable name is unsafe" do
    ENV["GRAFANA_VARIABLE_NAME"] = "app name"

    expect(described_class.call).to be_nil
  end

  def query_params(uri)
    CGI.parse(uri.query.to_s)
  end
end
