require "open-uri"
require "shellwords"

class Project < ApplicationRecord
  SCREENSHOT_OPEN_TIMEOUT = 5
  SCREENSHOT_READ_TIMEOUT = 10
  VPS_ROOT = "/srv/apps"
  SAFE_VPS_PATH_PATTERN = %r{\A#{Regexp.escape(VPS_ROOT)}/[A-Za-z0-9._/-]+\z}

  has_many :deployments, dependent: :destroy
  has_many :cron_jobs, dependent: :destroy
  has_many :pings, dependent: :destroy
  has_many :github_commits, dependent: :destroy
  has_many :github_pull_requests, dependent: :destroy
  has_one_attached :screenshot

  enum :status, { online: 0, offline: 1, unknown: 2 }, default: :unknown
  enum :kind, { app: "app", service: "service", cron: "cron" }, default: :app

  before_validation :sync_production_branch
  before_save :update_status_changed_at, if: :status_changed?

  validates :name, :slug, :vps_path, presence: true
  validates :production_url, :repo_url, :branch, presence: true, if: :app?

  validates :slug, uniqueness: true
  validates :status, inclusion: { in: %w[online offline unknown] }

  validate :repo_url_must_be_github_https, if: :repo_url_required?
  validate :production_url_must_be_http_url
  validate :vps_path_must_be_allowed

  def github_repo
    return "No GitHub repository" if repo_url.blank?

    URI.parse(repo_url).path.sub(/^\//, "").sub(/\.git$/, "")
  end

  def deploy_command
    bash_command("cd #{Shellwords.escape(vps_path)} && ./deploy.sh")
  end

  def cron_status_command
    bash_command("cd #{Shellwords.escape(vps_path)} && ./status.sh")
  end

  def runtime_monitoring_enabled_label
    runtime_monitoring_enabled? ? "Enabled" : "Disabled"
  end

  def cron_monitoring_enabled_label
    cron_monitoring_enabled? ? "Enabled" : "Disabled"
  end

  def runtime_status
    return "disabled" unless runtime_monitoring_enabled?

    status
  end

  def runtime_status_label
    case runtime_status
    when "online"
      "Online"
    when "offline"
      "Offline"
    when "disabled"
      "Disabled"
    else
      "Unknown"
    end
  end

  def runtime_status_tone
    case runtime_status
    when "online"
      :success
    when "offline"
      :danger
    when "disabled"
      :muted
    else
      :neutral
    end
  end

  def runtime_status_icon
    case runtime_status
    when "online"
      :circle_check
    when "offline"
      :circle_xmark
    else
      :circle_question
    end
  end

  def runtime_needs_attention?
    runtime_monitoring_enabled? && offline?
  end

  def effective_production_branch
    production_branch.presence || branch.presence || "master"
  end

  def prod_needs_deploy?
    commits_behind.to_i.positive?
  end

  def status_duration_seconds
    return nil unless status_changed_at

    (Time.current - status_changed_at).to_i
  end

  def status_duration_human
    return nil unless status_changed_at

    seconds = status_duration_seconds
    return "à l'instant" if seconds < 60

    minutes = seconds / 60
    return "depuis #{minutes} min" if minutes < 60

    hours = minutes / 60
    return "depuis #{hours} h" if hours < 24

    days = hours / 24
    return "depuis #{days} j" if days < 30

    months = days / 30
    "depuis #{months} mois"
  end

  def staging_sync_status
    return :not_configured if staging_branch.blank?
    return :synced if staging_commits_ahead.to_i.zero? && staging_commits_behind.to_i.zero?
    return :ahead if staging_commits_ahead.to_i.positive? && staging_commits_behind.to_i.zero?
    return :behind if staging_commits_ahead.to_i.zero? && staging_commits_behind.to_i.positive?

    :diverged
  end

  def staging_sync_label
    case staging_sync_status
    when :not_configured
      "Non configuré"
    when :synced
      "Synchronisé avec #{effective_production_branch}"
    when :ahead
      "+#{staging_commits_ahead} commit#{'s' if staging_commits_ahead > 1} (en avance)"
    when :behind
      "-#{staging_commits_behind} commit#{'s' if staging_commits_behind > 1} (en retard)"
    when :diverged
      "+#{staging_commits_ahead} / -#{staging_commits_behind}"
    end
  end

  def staging_sync_tone
    case staging_sync_status
    when :synced
      :success
    when :ahead
      :info
    when :behind, :diverged
      :warning
    else
      :neutral
    end
  end

  def maintenance_command(enabled)
    action = enabled ? "touch" : "rm -f"
    bash_command("#{action} #{Shellwords.escape(maintenance_flag_path)}")
  end

  def cron_summary_status
    return "disabled" unless cron_monitoring_enabled?

    jobs = loaded_or_query_cron_jobs
    return "not_reported" if jobs.empty?

    return "failed" if jobs.any?(&:failed?)
    return "never_run" if jobs.any?(&:never_run?)
    return "unknown" if jobs.any?(&:unknown?)
    return "ok" if jobs.all?(&:success?)

    "unknown"
  end

  def cron_needs_attention?
    %w[failed unknown never_run not_reported].include?(cron_summary_status)
  end

  def cron_summary_label
    case cron_summary_status
    when "disabled"
      "Disabled"
    when "ok"
      "OK"
    when "failed"
      "Failed"
    when "never_run"
      "Never run"
    when "not_reported"
      "Not reported"
    else
      "Unknown"
    end
  end

  def cron_summary_tone
    case cron_summary_status
    when "disabled"
      :neutral
    when "ok"
      :success
    when "failed"
      :danger
    when "never_run", "not_reported", "unknown"
      :warning
    else
      :muted
    end
  end

  def cron_summary_icon
    case cron_summary_status
    when "disabled"
      :clock
    when "ok"
      :circle_check
    when "failed"
      :circle_xmark
    when "never_run"
      :circle_play
    when "not_reported"
      :circle_question
    else
      :triangle_exclamation
    end
  end

  def latest_ping
    if pings.loaded?
      pings.max_by { |ping| ping.checked_at || ping.created_at }
    else
      pings.order(checked_at: :desc, created_at: :desc).first
    end
  end

  def open_pull_requests_count
    count_github_pull_requests_by_state("open")
  end

  def merged_pull_requests_count
    count_github_pull_requests_by_state("merged")
  end

  def fresh_screenshot_url
    return nil unless ENV["APIFLASH_ACCESS_KEY"].present? && production_url.present?

    apiflash_screenshot_url(width: 1280, height: 720)
  end

  def regenerate_screenshot!(force: false)
    return false if screenshot.attached? && !force
    return false unless ENV["APIFLASH_ACCESS_KEY"].present?

    url = fresh_screenshot_url
    return false unless url

    URI.open(url, open_timeout: SCREENSHOT_OPEN_TIMEOUT, read_timeout: SCREENSHOT_READ_TIMEOUT) do |io|
      screenshot.attach(io: io, filename: "#{slug}.jpg", content_type: "image/jpeg")
    end

    true
  rescue OpenURI::HTTPError, Net::OpenTimeout, Net::ReadTimeout, SocketError, IOError, SystemCallError => e
    Rails.logger.warn("Screenshot regeneration failed for project #{id || slug}: #{e.class}: #{e.message}")
    false
  end

  private

  def repo_url_required?
    app? || repo_url.present?
  end

  def maintenance_flag_path
    File.join(vps_path, "maintenance.on")
  end

  def bash_command(command)
    "bash -lc #{Shellwords.escape(command)}"
  end

  def count_github_pull_requests_by_state(state)
    if github_pull_requests.loaded?
      github_pull_requests.count { |pull_request| pull_request.state == state }
    else
      github_pull_requests.where(state: state).count
    end
  end

  def vps_path_must_be_allowed
    return if vps_path.blank?

    unless vps_path.match?(SAFE_VPS_PATH_PATTERN) && vps_path.exclude?("..")
      errors.add(:vps_path, "must stay under #{VPS_ROOT} and contain only safe path characters")
    end
  end

  def repo_url_must_be_github_https
    return if repo_url.blank?

    uri = URI.parse(repo_url)
    valid_path = uri.path.match?(%r{\A/[A-Za-z0-9-]+/[A-Za-z0-9._-]+(?:\.git)?\z})

    return if uri.is_a?(URI::HTTPS) && uri.host == "github.com" && uri.userinfo.blank? && valid_path

    errors.add(:repo_url, "must be a HTTPS GitHub repository URL")
  rescue URI::InvalidURIError
    errors.add(:repo_url, "must be a valid URL")
  end

  def production_url_must_be_http_url
    return if production_url.blank?

    uri = URI.parse(production_url)
    return if uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.blank?

    errors.add(:production_url, "must be a HTTP or HTTPS URL")
  rescue URI::InvalidURIError
    errors.add(:production_url, "must be a valid URL")
  end

  def apiflash_screenshot_url(width:, height:)
    query = URI.encode_www_form(
      access_key: ENV["APIFLASH_ACCESS_KEY"],
      url: production_url,
      width: width,
      height: height,
      format: "jpeg",
      quality: 80,
      fresh: true,
      wait_until: "page_loaded",
      delay: 2
    )

    URI::HTTPS.build(host: "api.apiflash.com", path: "/v1/urltoimage", query: query).to_s
  end

  def loaded_or_query_cron_jobs
    cron_jobs.to_a
  end

  def sync_production_branch
    self.production_branch = branch if branch.present? && (production_branch.blank? || (!production_branch_changed? && branch_changed?))
  end

  def update_status_changed_at
    self.status_changed_at = Time.current unless status_changed_at_changed?
  end
end
