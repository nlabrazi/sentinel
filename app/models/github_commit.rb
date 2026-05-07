class GithubCommit < ApplicationRecord
  belongs_to :project

  validates :sha, :message, presence: true
  validates :sha, uniqueness: { scope: :project_id }
  validate :html_url_must_be_github_https

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
