# frozen_string_literal: true

require "shellwords"
require "timeout"

class QuickCommandExecutionService
  COMMAND_TIMEOUT_SECONDS = 10
  MAX_OUTPUT_BYTES = 64.kilobytes
  TRUNCATED_NOTICE = "\n\n[Output truncated]\n"

  ALLOWED_BINARIES = %w[
    cat head tail grep egrep fgrep wc find ls diff stat file
    uptime df free ps pwd date whoami uname
    git docker docker-compose
  ].freeze

  FORBIDDEN_TOKENS = %w[
    sudo su rm rmdir mv cp chmod chown chgrp
    kill killall pkill reboot shutdown poweroff halt init
    mkfs dd wget curl nc netcat ncat telnet
    eval exec python python3 perl ruby php node npm yarn
  ].freeze

  FORBIDDEN_PATTERNS = [
    /\\/,                                  # Escape backslash
    /`/,                                   # Backticks
    /\$\(/,                                # Command substitution $(...)
    /[;&]/,                                # Command chaining / background (&, &&, ;, ;)
    /[><]/,                                # Redirection
    /\.\./,                                # Path traversal (..)
    /\.env/i,                              # .env files
    /\.key\b/i,                            # Private keys / master.key
    /\.pem\b/i,                            # Certificates / pem keys
    /id_rsa/i,                             # SSH keys
    /credentials(\.yml)?\.enc/i            # Encrypted Rails credentials
  ].freeze

  attr_reader :project, :raw_command

  def initialize(project, command)
    @project = project
    @raw_command = command.to_s.strip
  end

  def call
    validation_error = validate_command
    if validation_error
      return {
        success: false,
        exit_code: 1,
        stdout: "",
        stderr: validation_error,
        duration: 0.0
      }
    end

    execute_on_vps
  end

  private

  def validate_command
    return "Command cannot be empty." if @raw_command.blank?
    return "Command exceeds maximum length of 500 characters." if @raw_command.length > 500

    FORBIDDEN_PATTERNS.each do |pattern|
      if @raw_command.match?(pattern)
        return "Command contains forbidden syntax or accesses sensitive files."
      end
    end

    # Validate pipelines (|)
    segments = @raw_command.split("|").map(&:strip)
    return "Command contains an empty pipeline segment." if segments.any?(&:blank?)

    segments.each do |segment|
      segment_error = validate_segment(segment)
      return segment_error if segment_error
    end

    nil
  end

  def validate_segment(segment)
    begin
      tokens = Shellwords.split(segment)
    rescue ArgumentError => e
      return "Malformed command arguments: #{e.message}"
    end

    return "Empty command segment." if tokens.empty?

    binary = tokens.first

    # Reject any token that matches forbidden list
    tokens.each do |token|
      token_base = File.basename(token).downcase
      if FORBIDDEN_TOKENS.include?(token_base)
        return "Forbidden command or token: #{token_base}"
      end
    end

    # Check if binary is allowed
    if ALLOWED_BINARIES.include?(binary)
      return nil
    end

    # Check if binary is a safe local shell script: e.g. ./status.sh
    if binary.match?(%r{\A\./[a-zA-Z0-9_\-]+\.sh\z})
      return nil
    end

    # Check if calling `sh script.sh` or `bash script.sh`
    if %w[sh bash].include?(binary) && tokens[1]&.match?(%r{\A(\./)?[a-zA-Z0-9_\-]+\.sh\z})
      return nil
    end

    "Unauthorized command '#{binary}'. Allowed commands: #{ALLOWED_BINARIES.join(', ')}, or ./*.sh scripts."
  end

  def execute_on_vps
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ssh = SshExecutionService.new(@project)
    full_command = "cd #{Shellwords.escape(@project.vps_path)} && #{@raw_command}"

    result = Timeout.timeout(COMMAND_TIMEOUT_SECONDS) do
      ssh.execute(full_command)
    end

    duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time).round(2)
    exit_code = result[:exit_code].to_i
    success = exit_code.zero?

    {
      success: success,
      exit_code: exit_code,
      stdout: truncate_output(result[:stdout]),
      stderr: truncate_output(result[:stderr]),
      duration: duration
    }
  rescue Timeout::Error
    {
      success: false,
      exit_code: 124,
      stdout: "",
      stderr: "Command timed out after #{COMMAND_TIMEOUT_SECONDS}s.",
      duration: COMMAND_TIMEOUT_SECONDS.to_f
    }
  rescue StandardError => e
    {
      success: false,
      exit_code: 1,
      stdout: "",
      stderr: "SSH Execution Error: #{e.message}",
      duration: 0.0
    }
  end

  def truncate_output(output)
    text = output.to_s
    return text if text.bytesize <= MAX_OUTPUT_BYTES

    text.byteslice(0, MAX_OUTPUT_BYTES - TRUNCATED_NOTICE.bytesize) + TRUNCATED_NOTICE
  end
end
