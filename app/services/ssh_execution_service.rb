# Exécute une commande sur le VPS via SSH.
# Utilise les variables d'environnement pour la connexion.
class SshExecutionService
  COMMAND_TIMEOUT_SECONDS = ENV.fetch("SSH_COMMAND_TIMEOUT_SECONDS", 10.minutes.to_i).to_i
  CONNECT_TIMEOUT_SECONDS = ENV.fetch("SSH_CONNECT_TIMEOUT_SECONDS", 10).to_i
  SSH_KEY_PATH = ENV.fetch("SSH_KEY_PATH", "config/ssh_key/id_rsa")
  SSH_KNOWN_HOSTS_PATH = ENV.fetch("SSH_KNOWN_HOSTS_PATH", File.join(File.dirname(SSH_KEY_PATH), "known_hosts"))
  SSH_USER = ENV.fetch("VPS_USER", "control-panel")
  VPS_HOST = ENV.fetch("VPS_HOST", "vps.example.com")

  def initialize(project)
    @project = project
  end

  def execute(command)
    Timeout.timeout(COMMAND_TIMEOUT_SECONDS) do
      Net::SSH.start(VPS_HOST, SSH_USER, ssh_options) do |ssh|
        run_command(ssh, command)
      end
    end
  rescue Net::SSH::Exception, IOError, SystemCallError, Timeout::Error => e
    { exit_code: 1, stdout: "", stderr: e.message }
  end

  private

  def run_command(ssh, command)
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

  def ssh_options
    {
      auth_methods: %w[publickey],
      keys: [ SSH_KEY_PATH ],
      non_interactive: true,
      timeout: CONNECT_TIMEOUT_SECONDS,
      user_known_hosts_file: SSH_KNOWN_HOSTS_PATH,
      verify_host_key: :always
    }
  end
end
