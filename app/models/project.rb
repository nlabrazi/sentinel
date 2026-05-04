require "open-uri"

class Project < ApplicationRecord
  include ActiveStorage::Attached::Model
  has_many :deployments, dependent: :destroy
  has_many :cron_jobs, dependent: :destroy
  has_one_attached :screenshot

  validates :name, :slug, :repo_url, :branch, :production_url, :vps_path, presence: true
  validates :slug, uniqueness: true
  validates :status, inclusion: { in: %w[online offline unknown] }

  enum :status, { online: 0, offline: 1, unknown: 2 }, default: :unknown

  # Extrait le nom du dépôt GitHub depuis l'URL
  def github_repo
    URI.parse(repo_url).path.sub(/^\//, '').sub(/\.git$/, '')
  end

  # Commandes SSH prédéfinies
  def deploy_command
    "bash -lc 'cd #{vps_path} && ./deploy.sh'"
  end

  def cron_status_command
    "bash -lc 'cd #{vps_path} && ./status.sh'"
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
    return nil unless ENV['APIFLASH_ACCESS_KEY'].present?

    "https://api.apiflash.com/v1/urltoimage" \
      "?access_key=#{ENV['APIFLASH_ACCESS_KEY']}" \
      "&url=#{CGI.escape(production_url)}" \
      "&width=1280" \
      "&height=720" \
      "&format=jpeg" \
      "&quality=80" \
      "&fresh=true" \
      "&wait_until=page_loaded" \
      "&delay=2"
  end

  def regenerate_screenshot!
    return unless ENV['APIFLASH_ACCESS_KEY'].present?

    url = fresh_screenshot_url
    return unless url

    # Télécharge l'image depuis l'API et l'attache
    io = URI.open(url)
    screenshot.attach(io: io, filename: "#{slug}.jpg", content_type: "image/jpeg")
  end
end
