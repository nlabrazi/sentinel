# Interagit avec l'API GitHub pour obtenir les commits.
# Nécessite GITHUB_TOKEN dans les variables d'environnement.
class GithubService
  def initialize(project)
    @project = project
    @client = Octokit::Client.new(access_token: ENV["GITHUB_TOKEN"])
  end

  # Retourne le dernier commit de la branche principale sous forme d'objet Sawyer::Resource
  def latest_commit_on_branch
    branch_name = @project.effective_production_branch
    branch_ref = @client.ref(@project.github_repo, "heads/#{branch_name}")
    @client.commit(@project.github_repo, branch_ref[:object][:sha])
  rescue Octokit::Error, Faraday::Error => e
    log_github_error("latest commit lookup", e)
    nil
  end

  # Calcule le nombre de commits de différence entre le SHA donné et HEAD de la branche
  def commits_behind(base_sha)
    return 0 unless base_sha

    branch_name = @project.effective_production_branch
    comparison = @client.compare(@project.github_repo, base_sha, "heads/#{branch_name}")
    comparison[:ahead_by] || 0
  rescue Octokit::Error, Faraday::Error => e
    log_github_error("commit comparison", e)
    0
  end

  # Compare deux branches ou références via l'API GitHub.
  # Par défaut, compare la branche de production (base) et la branche staging (head).
  def compare_branches(base_branch = nil, head_branch = nil)
    base = base_branch.presence || @project.effective_production_branch
    head = head_branch.presence || @project.staging_branch

    return nil if base.blank? || head.blank?
    return nil if @project.repo_url.blank? || @project.github_repo == "No GitHub repository"

    comparison = @client.compare(@project.github_repo, base, head)

    ahead_by = comparison[:ahead_by] || 0
    behind_by = calculate_commits_behind(comparison, base)
    status = determine_branch_status(ahead_by, behind_by)

    {
      base_branch: base,
      head_branch: head,
      ahead_by: ahead_by,
      behind_by: behind_by,
      status: status,
      total_commits: comparison[:total_commits] || 0,
      html_url: comparison[:html_url],
      permalink_url: comparison[:permalink_url],
      commits: (comparison[:commits] || []).map { |commit| normalize_commit(commit) }
    }
  rescue Octokit::Error, Faraday::Error => e
    log_github_error("branch comparison (#{base}...#{head})", e)
    nil
  end

  def recent_commits(limit: 20)
    branch_name = @project.effective_production_branch
    @client.commits(@project.github_repo, sha: branch_name, per_page: limit).map do |commit|
      normalize_commit(commit)
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

  def calculate_commits_behind(comparison, base_branch)
    raw_behind = comparison[:behind_by].to_i
    return 0 if raw_behind.zero?

    merge_base_sha = comparison.dig(:merge_base_commit, :sha)
    return raw_behind if merge_base_sha.blank?

    base_commit = comparison[:base_commit]
    return raw_behind if base_commit.blank?

    base_commit_sha = extract_commit_sha(base_commit)
    return 0 if base_commit_sha == merge_base_sha

    if comparison[:ahead_by].to_i.zero?
      base_tree = comparison.dig(:base_commit, :commit, :tree, :sha)
      merge_base_tree = comparison.dig(:merge_base_commit, :commit, :tree, :sha)
      return 0 if base_tree.present? && base_tree == merge_base_tree
    end

    base_parents = extract_parent_shas(base_commit)
    return 0 if base_parents.include?(merge_base_sha)

    commits_since_merge = count_commits_on_base_since_merge(base_branch, merge_base_sha)
    commits_since_merge.nil? ? raw_behind : commits_since_merge
  end

  def count_commits_on_base_since_merge(base_branch, merge_base_sha)
    recent_commits = @client.commits(@project.github_repo, sha: base_branch, per_page: 30)
    count = 0
    found = false

    recent_commits.each do |c|
      sha = extract_commit_sha(c)
      parents = extract_parent_shas(c)

      if sha == merge_base_sha || parents.include?(merge_base_sha)
        found = true
        break
      end

      count += 1
    end

    found ? count : nil
  rescue Octokit::Error, Faraday::Error => e
    log_github_error("counting commits behind on #{base_branch}", e)
    nil
  end

  def extract_commit_sha(commit)
    return commit[:sha] if commit.is_a?(Hash) && commit.key?(:sha)
    return commit["sha"] if commit.is_a?(Hash) && commit.key?("sha")
    return commit.sha if commit.respond_to?(:sha)
    return commit[:sha] if commit.respond_to?(:[]) && commit[:sha].present?

    nil
  end

  def extract_parent_shas(commit)
    parents = commit[:parents] || (commit.respond_to?(:parents) ? commit.parents : nil) || []
    parents.map do |p|
      if p.is_a?(Hash)
        p[:sha] || p["sha"]
      elsif p.respond_to?(:sha)
        p.sha
      elsif p.respond_to?(:[])
        p[:sha] || p["sha"]
      end
    end.compact
  end

  def determine_branch_status(ahead_by, behind_by)
    if ahead_by.zero? && behind_by.zero?
      "identical"
    elsif ahead_by.positive? && behind_by.zero?
      "ahead"
    elsif ahead_by.zero? && behind_by.positive?
      "behind"
    else
      "diverged"
    end
  end

  def normalize_commit(commit)
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

  def pull_request_state(pull_request)
    return "merged" if pull_request[:merged_at].present?

    pull_request[:state].presence || "closed"
  end

  def log_github_error(action, error)
    branch_name = @project.effective_production_branch
    Rails.logger.warn(
      "GitHub #{action} failed for #{@project.github_repo}@#{branch_name}: #{error.class}: #{error.message}"
    )
  end
end
