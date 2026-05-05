# Orchestre un déploiement complet :
# 1. Récupère le dernier commit distant
# 2. Crée un enregistrement Deployment
# 3. Exécute le script deploy.sh sur le VPS via SSH
# 4. Met à jour le statut du projet si succès
class DeployProjectService
  def initialize(project, triggered_by: "web")
    @project = project
    @triggered_by = triggered_by
  end

  def call
    return false if @project.deployments.running.exists?

    github = GithubService.new(@project)
    latest_commit = github.latest_commit_on_branch
    return false unless latest_commit

    commit_sha = latest_commit[:sha]

    deployment = @project.deployments.create!(
      commit_sha: commit_sha,
      status: :running,
      triggered_by: @triggered_by
    )

    start_time = Time.current
    ssh = SshExecutionService.new(@project)
    result = ssh.execute(@project.deploy_command)

    duration = (Time.current - start_time).to_i
    success = result[:exit_code].zero?

    deployment.update!(
      status: success ? :success : :failed,
      duration: duration,
      log: [ result[:stdout], result[:stderr] ].compact.join("\n")
    )

    if success
      @project.update!(
        last_commit_deployed: commit_sha,
        commits_behind: 0
      )
       @project.regenerate_screenshot!
    end

    success
  rescue StandardError => e
    deployment&.update!(status: :failed, log: e.message) if deployment
    false
  end
end
