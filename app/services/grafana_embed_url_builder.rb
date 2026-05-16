require "uri"

class GrafanaEmbedUrlBuilder
  DEFAULT_DASHBOARD_SLUG = "applications-overview"
  DEFAULT_VARIABLE_NAME = "app"
  DEFAULT_THEME = "dark"
  DEFAULT_ORG_ID = "1"
  DEFAULT_FROM = "now-6h"
  DEFAULT_TO = "now"
  DEFAULT_TIMEZONE = "browser"
  DEFAULT_GLOBAL_VARIABLE_VALUE = "All"
  VARIABLE_NAME_PATTERN = /\A[A-Za-z0-9_-]+\z/

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(project: nil, panel_id: nil, kiosk: false, theme: nil, from: nil, to: nil, env: ENV)
    @project = project
    @panel_id = panel_id
    @kiosk = kiosk
    @theme = theme
    @from = from
    @to = to
    @env = env
  end

  def call
    base_uri = grafana_base_uri
    uid = dashboard_uid
    variable_name = grafana_variable_name
    variable_value = grafana_variable_value

    return nil unless base_uri && uid && variable_name
    return nil if @project && variable_value.blank?

    uri = base_uri.dup
    uri.path = dashboard_path(base_uri.path, uid)
    uri.query = URI.encode_www_form(query_params(variable_name, variable_value))
    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  private

  def grafana_base_uri
    value = env_value("GRAFANA_BASE_URL")
    return nil unless value

    uri = URI.parse(value)
    return nil unless uri.is_a?(URI::HTTP) && uri.host.present?
    return nil if uri.userinfo.present? || uri.query.present? || uri.fragment.present?

    uri
  end

  def dashboard_uid
    env_value("GRAFANA_DASHBOARD_UID")
  end

  def dashboard_slug
    env_value("GRAFANA_DASHBOARD_SLUG", DEFAULT_DASHBOARD_SLUG)
  end

  def grafana_variable_name
    value = env_value("GRAFANA_VARIABLE_NAME", DEFAULT_VARIABLE_NAME)
    return nil unless value&.match?(VARIABLE_NAME_PATTERN)

    value
  end

  def grafana_variable_value
    if @project
      @project.grafana_app_value.to_s.strip.presence
    else
      env_value("GRAFANA_GLOBAL_VARIABLE_VALUE", DEFAULT_GLOBAL_VARIABLE_VALUE)
    end
  end

  def query_params(variable_name, variable_value)
    params = []
    params << [ "orgId", env_value("GRAFANA_ORG_ID", DEFAULT_ORG_ID) ]
    params << [ "from", option_value(@from, "GRAFANA_DEFAULT_FROM", DEFAULT_FROM) ]
    params << [ "to", option_value(@to, "GRAFANA_DEFAULT_TO", DEFAULT_TO) ]
    params << [ "timezone", env_value("GRAFANA_DEFAULT_TIMEZONE", DEFAULT_TIMEZONE) ]
    params << [ "refresh", env_value("GRAFANA_REFRESH") ] if env_value("GRAFANA_REFRESH")
    params << [ "theme", option_value(@theme, "GRAFANA_DEFAULT_THEME", DEFAULT_THEME) ]
    params << [ "panelId", panel_id ] if panel_id
    append_kiosk_param(params)
    params << [ "var-#{variable_name}", variable_value ] if variable_value.present?
    params
  end

  def dashboard_path(base_path, uid)
    segments = base_path.to_s.split("/").reject(&:blank?)
    segments += [
      panel_id ? "d-solo" : "d",
      path_segment(uid),
      path_segment(dashboard_slug)
    ]

    "/#{segments.join("/")}"
  end

  def append_kiosk_param(params)
    return if @kiosk.blank?

    params << [ "kiosk", @kiosk == true ? nil : @kiosk.to_s ]
  end

  def panel_id
    @panel_id.to_s.strip.presence || env_value("GRAFANA_PANEL_ID")
  end

  def option_value(value, env_key, default)
    value.to_s.strip.presence || env_value(env_key, default)
  end

  def env_value(key, default = nil)
    @env[key].to_s.strip.presence || default
  end

  def path_segment(value)
    URI.encode_www_form_component(value.to_s).gsub("+", "%20")
  end
end
