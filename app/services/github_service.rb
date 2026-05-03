# Interagit avec l'API GitHub pour obtenir les commits.
# Nécessite GITHUB_TOKEN dans les variables d'environnement.
class GithubService
  def initialize(project)
    @project = project
    @client = Octokit::Client.new(access_token: ENV.fetch('GITHUB_TOKEN'))
  end

  # Retourne le dernier commit de la branche principale sous forme d'objet Sawyer::Resource
  def latest_commit_on_branch
    branch_ref = @client.ref(@project.github_repo, "heads/#{@project.branch}")
    @client.commit(@project.github_repo, branch_ref[:object][:sha])
  rescue Octokit::NotFound
    nil
  end

  # Calcule le nombre de commits de différence entre le SHA donné et HEAD de la branche
  def commits_behind(base_sha)
    return 0 unless base_sha

    comparison = @client.compare(@project.github_repo, base_sha, "heads/#{@project.branch}")
    comparison[:behind_by] || 0
  rescue Octokit::Error
    0
  end
end
