# Interagit avec l'API GitHub pour obtenir les commits.
# Nécessite GITHUB_TOKEN dans les variables d'environnement.
class GithubService
  def initialize(project)
    @project = project
    @client = Octokit::Client.new(access_token: ENV["GITHUB_TOKEN"])
  end

  # Retourne le dernier commit de la branche principale sous forme d'objet Sawyer::Resource
  def latest_commit_on_branch
    branch_ref = @client.ref(@project.github_repo, "heads/#{@project.branch}")
    @client.commit(@project.github_repo, branch_ref[:object][:sha])
  rescue Octokit::Error, Faraday::Error => e
    log_github_error("latest commit lookup", e)
    nil
  end

  # Calcule le nombre de commits de différence entre le SHA donné et HEAD de la branche
  def commits_behind(base_sha)
    return 0 unless base_sha

    comparison = @client.compare(@project.github_repo, base_sha, "heads/#{@project.branch}")
    comparison[:ahead_by] || 0
  rescue Octokit::Error, Faraday::Error => e
    log_github_error("commit comparison", e)
    0
  end

  def recent_commits(limit: 20)
    @client.commits(@project.github_repo, sha: @project.branch, per_page: limit).map do |commit|
      commit_payload = commit[:commit] || {}
      author_payload = commit_payload[:author] || {}
      committer_payload = commit_payload[:committer] || {}
      github_author = commit[:author] || {}

      {
        sha: commit[:sha],
        message: commit_payload[:message].to_s.lines.first.to_s.strip,
        author_name: author_payload[:name],
        author_login: github_author[:login],
        authored_at: author_payload[:date],
        committed_at: committer_payload[:date],
        html_url: commit[:html_url]
      }
    end
  rescue Octokit::Error, Faraday::Error => e
    log_github_error("recent commits lookup", e)
    []
  end

  def recent_pull_requests(limit: 20)
    @client.pull_requests(
      @project.github_repo,
      state: "all",
      sort: "updated",
      direction: "desc",
      per_page: limit
    ).map do |pull_request|
      {
        number: pull_request[:number],
        title: pull_request[:title],
        state: pull_request_state(pull_request),
        draft: pull_request[:draft] || false,
        author_login: (pull_request[:user] || {})[:login],
        head_ref: (pull_request[:head] || {})[:ref],
        base_ref: (pull_request[:base] || {})[:ref],
        opened_at: pull_request[:created_at],
        closed_at: pull_request[:closed_at],
        merged_at: pull_request[:merged_at],
        github_updated_at: pull_request[:updated_at],
        html_url: pull_request[:html_url]
      }
    end
  rescue Octokit::Error, Faraday::Error => e
    log_github_error("recent pull requests lookup", e)
    []
  end

  private

  def pull_request_state(pull_request)
    return "merged" if pull_request[:merged_at].present?

    pull_request[:state].presence || "closed"
  end

  def log_github_error(action, error)
    Rails.logger.warn(
      "GitHub #{action} failed for #{@project.github_repo}@#{@project.branch}: #{error.class}: #{error.message}"
    )
  end
end
