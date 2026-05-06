require "open-uri"
require "shellwords"

class Project < ApplicationRecord
  SCREENSHOT_OPEN_TIMEOUT = 5
  SCREENSHOT_READ_TIMEOUT = 10

  include ActiveStorage::Attached::Model
  has_many :deployments, dependent: :destroy
  has_many :cron_jobs, dependent: :destroy
  has_one_attached :screenshot

  validates :name, :slug, :repo_url, :branch, :production_url, :vps_path, presence: true
  validates :slug, uniqueness: true
  validates :status, inclusion: { in: %w[online offline unknown] }
  validate :repo_url_must_be_github_https
  validate :production_url_must_be_http_url
  validate :vps_path_must_be_allowed

  enum :status, { online: 0, offline: 1, unknown: 2 }, default: :unknown

  # Extrait le nom du dépôt GitHub depuis l'URL
  def github_repo
    URI.parse(repo_url).path.sub(/^\//, "").sub(/\.git$/, "")
  end

  # Commandes SSH prédéfinies
  def deploy_command
    bash_command("cd #{Shellwords.escape(vps_path)} && ./deploy.sh")
  end

  def cron_status_command
    bash_command("cd #{Shellwords.escape(vps_path)} && ./status.sh")
  end

  def maintenance_command(enabled)
    action = enabled ? "touch" : "rm -f"
    bash_command("#{action} #{Shellwords.escape(maintenance_flag_path)}")
  end

  # app/models/project.rb
  def screenshot_url(width: 1280, height: 720)
    "https://api.apiflash.com/v1/urltoimage" \
    "?access_key=#{ENV['APIFLASH_ACCESS_KEY']}" \
    "&url=#{CGI.escape(production_url)}" \
    "&width=#{width}" \
    "&height=#{height}" \
    "&format=jpeg" \
    "&quality=80" \
    "&fresh=true" \
    "&full_page=false" \
    "&wait_until=page_loaded" \
    "&delay=2"
  end

  def fresh_screenshot_url
    return nil unless ENV["APIFLASH_ACCESS_KEY"].present?

    "https://api.apiflash.com/v1/urltoimage" \
      "?access_key=#{ENV["APIFLASH_ACCESS_KEY"]}" \
      "&url=#{CGI.escape(production_url)}" \
      "&width=1280" \
      "&height=720" \
      "&format=jpeg" \
      "&quality=80" \
      "&fresh=true" \
      "&wait_until=page_loaded" \
      "&delay=2"
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

  def maintenance_flag_path
    File.join(vps_path, "maintenance.on")
  end

  def bash_command(command)
    "bash -lc #{Shellwords.escape(command)}"
  end

  def vps_path_must_be_allowed
    return if vps_path.blank?

    unless vps_path.match?(%r{\A/srv/projects/[A-Za-z0-9._/-]+\z}) && vps_path.exclude?("..")
      errors.add(:vps_path, "must stay under /srv/projects and contain only safe path characters")
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
end
