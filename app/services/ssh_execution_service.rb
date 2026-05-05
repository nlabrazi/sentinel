# Exécute une commande sur le VPS via SSH.
# Utilise les variables d'environnement pour la connexion.
class SshExecutionService
  SSH_KEY_PATH = ENV.fetch("SSH_KEY_PATH", "config/ssh_key/id_rsa")
  SSH_USER = ENV.fetch("VPS_USER", "control-panel")
  VPS_HOST = ENV.fetch("VPS_HOST", "vps.example.com")

  def initialize(project)
    @project = project
  end

  def execute(command)
    Net::SSH.start(VPS_HOST, SSH_USER, keys: [ SSH_KEY_PATH ]) do |ssh|
      stdout = +""
      stderr = +""
      exit_code = nil

      ssh.open_channel do |channel|
        channel.exec(command) do |_ch, success|
          unless success
            exit_code = 1
            stderr << "Could not execute command"
            next
          end

          channel.on_data { |_ch, data| stdout << data }
          channel.on_extended_data { |_ch, _type, data| stderr << data }
          channel.on_request("exit-status") { |_ch, data| exit_code = data.read_long }
        end
      end

      ssh.loop
      { exit_code: exit_code || 1, stdout: stdout, stderr: stderr }
    end
  rescue Net::SSH::Exception, IOError, SystemCallError => e
    { exit_code: 1, stdout: "", stderr: e.message }
  end
end
