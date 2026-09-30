class MetricsController < ActionController::API
  before_action :authenticate_metrics

  def index
    response.headers["Cache-Control"] = "no-store"
    render plain: CronMetricsService.new.call, content_type: "text/plain; version=0.0.4; charset=utf-8"
  end

  private

  def authenticate_metrics
    expected = ENV["PROMETHEUS_METRICS_TOKEN"]
    provided = request.authorization.to_s[/\ABearer (\S+)\z/, 1]
    return if expected.present? && provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, expected)

    response.headers["WWW-Authenticate"] = 'Bearer realm="metrics"'
    head :unauthorized
  end
end
