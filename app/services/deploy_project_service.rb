# Orchestre un déploiement complet :
# 1. Récupère le dernier commit distant
# 2. Crée un enregistrement Deployment
# 3. Exécute le script deploy.sh sur le VPS via SSH
# 4. Met à jour le statut du projet si succès
class DeployProjectService
  MAX_LOG_BYTES = 64.kilobytes
  TRUNCATED_LOG_NOTICE = "\n\n[Log truncated]\n"

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
    deployment = start_deployment(commit_sha)
    return false unless deployment

    start_time = Time.current
    ssh = SshExecutionService.new(@project)
    result = ssh.execute(@project.deploy_command)

    duration = (Time.current - start_time).to_i
    success = result[:exit_code].zero?

    deployment.update!(
      status: success ? :success : :failed,
      duration: duration,
      log: deployment_log(result)
    )

    if success
      @project.update!(
        last_commit_deployed: commit_sha,
        latest_commit_available: commit_sha,
        commits_behind: 0
      )
      @project.regenerate_screenshot!
    end

    success
  rescue StandardError => e
    deployment&.update!(status: :failed, log: truncate_log(e.message)) if deployment
    false
  end

  private

  def start_deployment(commit_sha)
    @project.with_lock do
      return nil if @project.deployments.running.exists?

      @project.deployments.create!(
        commit_sha: commit_sha,
        status: :running,
        triggered_by: @triggered_by
      )
    end
  end

  def deployment_log(result)
    truncate_log([ result[:stdout], result[:stderr] ].compact.join("\n"))
  end

  def truncate_log(log)
    return log if log.bytesize <= MAX_LOG_BYTES

    log.byteslice(0, MAX_LOG_BYTES - TRUNCATED_LOG_NOTICE.bytesize) + TRUNCATED_LOG_NOTICE
  end
end
