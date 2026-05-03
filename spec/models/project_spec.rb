class Project < ApplicationRecord
  has_many :deployments, dependent: :destroy
  has_many :cron_jobs, dependent: :destroy

  validates :name, :slug, :repo_url, :branch, :production_url, :vps_path, presence: true
  validates :slug, uniqueness: true
  validates :status, inclusion: { in: %w[online offline unknown] }

  enum :status, { online: 0, offline: 1, unknown: 2 }, default: :unknown

end
