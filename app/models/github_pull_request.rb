class GithubPullRequest < ApplicationRecord
  belongs_to :project

  STATES = %w[open closed merged].freeze

  validates :number, :title, :state, presence: true
  validates :number, uniqueness: { scope: :project_id }
  validates :state, inclusion: { in: STATES }
  validate :html_url_must_be_github_https

  def merged?
    state == "merged"
  end

  private

  def html_url_must_be_github_https
    return if html_url.blank?

    uri = URI.parse(html_url)
    return if uri.is_a?(URI::HTTPS) && uri.host == "github.com" && uri.userinfo.blank?

    errors.add(:html_url, "must be a HTTPS GitHub URL")
  rescue URI::InvalidURIError
    errors.add(:html_url, "must be a valid URL")
  end
end
