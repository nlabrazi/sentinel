class GithubPullRequestsSyncService
  DEFAULT_LIMIT = 20

  def initialize(project, limit: DEFAULT_LIMIT)
    @project = project
    @limit = limit
  end

  def call
    pull_requests = GithubService.new(@project).recent_pull_requests(limit: @limit)
    return 0 if pull_requests.blank?

    pull_requests.sum { |pull_request| upsert_pull_request(pull_request) ? 1 : 0 }
  end

  private

  def upsert_pull_request(pull_request)
    number = pull_request[:number]
    return false if number.blank?

    github_pull_request = @project.github_pull_requests.find_or_initialize_by(number: number)
    github_pull_request.update!(
      title: pull_request[:title].presence || "Pull request ##{number}",
      state: pull_request[:state],
      draft: pull_request[:draft],
      author_login: pull_request[:author_login],
      head_ref: pull_request[:head_ref],
      base_ref: pull_request[:base_ref],
      opened_at: pull_request[:opened_at],
      closed_at: pull_request[:closed_at],
      merged_at: pull_request[:merged_at],
      github_updated_at: pull_request[:github_updated_at],
      html_url: pull_request[:html_url]
    )
  end
end
