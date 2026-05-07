class GithubCommitsSyncService
  DEFAULT_LIMIT = 20

  def initialize(project, limit: DEFAULT_LIMIT)
    @project = project
    @limit = limit
  end

  def call
    commits = GithubService.new(@project).recent_commits(limit: @limit)
    return 0 if commits.blank?

    commits.sum { |commit| upsert_commit(commit) ? 1 : 0 }
  end

  private

  def upsert_commit(commit)
    sha = commit[:sha].to_s
    return false if sha.blank?

    github_commit = @project.github_commits.find_or_initialize_by(sha: sha)
    github_commit.update!(
      message: commit[:message].presence || sha,
      author_name: commit[:author_name],
      author_login: commit[:author_login],
      authored_at: commit[:authored_at],
      committed_at: commit[:committed_at],
      html_url: commit[:html_url]
    )
  end
end
