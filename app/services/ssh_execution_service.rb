# Exécute une commande sur le VPS via SSH.
# Utilise les variables d'environnement pour la connexion.
class SshExecutionService
  SSH_KEY_PATH = ENV.fetch('SSH_KEY_PATH', 'config/ssh_key/id_rsa')
  SSH_USER = ENV.fetch('VPS_USER', 'control-panel')
  VPS_HOST = ENV.fetch('VPS_HOST', 'vps.example.com')

  def initialize(project)
    @project = project
  end

  def execute(command)
    Net::SSH.start(VPS_HOST, SSH_USER, keys: [SSH_KEY_PATH]) do |ssh|
      result = ssh.exec!(command)
      { exit_code: 0, stdout: result, stderr: '' }
    end
  rescue Net::SSH::Exception => e
    { exit_code: 1, stdout: '', stderr: e.message }
  end
end
