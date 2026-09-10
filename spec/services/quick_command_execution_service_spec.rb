# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QuickCommandExecutionService, type: :service do
  let(:project) { build(:project, vps_path: '/srv/apps/my-app') }
  let(:ssh_service) { instance_double(SshExecutionService) }

  before do
    allow(SshExecutionService).to receive(:new).with(project).and_return(ssh_service)
  end

  describe 'command validation' do
    describe 'allowed commands' do
      it 'allows basic reading commands like cat' do
        allow(ssh_service).to receive(:execute).with("cd /srv/apps/my-app && cat README.md")
          .and_return(exit_code: 0, stdout: "Project docs\n", stderr: "")

        result = described_class.new(project, "cat README.md").call

        expect(result[:success]).to be true
        expect(result[:stdout]).to eq("Project docs\n")
        expect(result[:exit_code]).to eq(0)
      end

      it 'allows directory listing with arguments' do
        allow(ssh_service).to receive(:execute).with("cd /srv/apps/my-app && ls -la")
          .and_return(exit_code: 0, stdout: "total 4\n", stderr: "")

        result = described_class.new(project, "ls -la").call

        expect(result[:success]).to be true
      end

      it 'allows git status' do
        allow(ssh_service).to receive(:execute).with("cd /srv/apps/my-app && git status")
          .and_return(exit_code: 0, stdout: "On branch main\n", stderr: "")

        result = described_class.new(project, "git status").call

        expect(result[:success]).to be true
      end

      it 'allows docker compose ps' do
        allow(ssh_service).to receive(:execute).with("cd /srv/apps/my-app && docker compose ps")
          .and_return(exit_code: 0, stdout: "web running\n", stderr: "")

        result = described_class.new(project, "docker compose ps").call

        expect(result[:success]).to be true
      end

      it 'allows local shell scripts matching ./*.sh' do
        allow(ssh_service).to receive(:execute).with("cd /srv/apps/my-app && ./status.sh")
          .and_return(exit_code: 0, stdout: "OK\n", stderr: "")

        result = described_class.new(project, "./status.sh").call

        expect(result[:success]).to be true
      end

      it 'allows pipelines between allowed commands' do
        allow(ssh_service).to receive(:execute).with("cd /srv/apps/my-app && tail -n 50 log/production.log | grep -i error")
          .and_return(exit_code: 0, stdout: "ERROR: db connection\n", stderr: "")

        result = described_class.new(project, "tail -n 50 log/production.log | grep -i error").call

        expect(result[:success]).to be true
      end

      it 'allows system diagnostic commands' do
        allow(ssh_service).to receive(:execute).with("cd /srv/apps/my-app && uptime")
          .and_return(exit_code: 0, stdout: "up 42 days\n", stderr: "")

        result = described_class.new(project, "uptime").call

        expect(result[:success]).to be true
      end
    end

    describe 'forbidden and dangerous commands' do
      it 'rejects empty or blank commands' do
        result = described_class.new(project, "   ").call

        expect(result[:success]).to be false
        expect(result[:stderr]).to include("Command cannot be empty")
        expect(SshExecutionService).not_to have_received(:new)
      end

      it 'rejects commands exceeding 500 characters' do
        result = described_class.new(project, "cat " + "a" * 500).call

        expect(result[:success]).to be false
        expect(result[:stderr]).to include("maximum length")
      end

      it 'rejects path traversal with ..' do
        result = described_class.new(project, "cat ../../etc/passwd").call

        expect(result[:success]).to be false
        expect(result[:stderr]).to include("forbidden syntax")
      end

      it 'rejects reading .env files' do
        result = described_class.new(project, "cat .env").call

        expect(result[:success]).to be false
        expect(result[:stderr]).to include("forbidden syntax")
      end

      it 'rejects reading private keys or master.key' do
        result = described_class.new(project, "cat config/master.key").call

        expect(result[:success]).to be false
        expect(result[:stderr]).to include("forbidden syntax")
      end

      it 'rejects redirection with >' do
        result = described_class.new(project, "ls > test.txt").call

        expect(result[:success]).to be false
        expect(result[:stderr]).to include("forbidden syntax")
      end

      it 'rejects command chaining with ;' do
        result = described_class.new(project, "ls; cat README.md").call

        expect(result[:success]).to be false
        expect(result[:stderr]).to include("forbidden syntax")
      end

      it 'rejects command chaining with &&' do
        result = described_class.new(project, "ls && git status").call

        expect(result[:success]).to be false
        expect(result[:stderr]).to include("forbidden syntax")
      end

      it 'rejects background execution with &' do
        result = described_class.new(project, "uptime &").call

        expect(result[:success]).to be false
        expect(result[:stderr]).to include("forbidden syntax")
      end

      it 'rejects command substitution with $(' do
        result = described_class.new(project, "cat $(whoami)").call

        expect(result[:success]).to be false
        expect(result[:stderr]).to include("forbidden syntax")
      end

      it 'rejects command substitution with backticks' do
        result = described_class.new(project, "cat `whoami`").call

        expect(result[:success]).to be false
        expect(result[:stderr]).to include("forbidden syntax")
      end

      it 'rejects destructive commands like rm' do
        result = described_class.new(project, "rm -rf tmp").call

        expect(result[:success]).to be false
        expect(result[:stderr]).to include("Forbidden command or token: rm")
      end

      it 'rejects privilege escalation like sudo' do
        result = described_class.new(project, "sudo systemctl restart nginx").call

        expect(result[:success]).to be false
        expect(result[:stderr]).to include("Forbidden command or token: sudo")
      end

      it 'rejects unauthorized binaries' do
        result = described_class.new(project, "curl http://evil.com").call

        expect(result[:success]).to be false
        expect(result[:stderr]).to include("Forbidden command or token: curl")
      end

      it 'rejects pipelines containing unauthorized binaries' do
        result = described_class.new(project, "cat README.md | nc -l 1234").call

        expect(result[:success]).to be false
        expect(result[:stderr]).to include("Forbidden command or token: nc")
      end
    end
  end

  describe 'execution error handling' do
    it 'handles non-zero exit codes cleanly' do
      allow(ssh_service).to receive(:execute).with("cd /srv/apps/my-app && cat non_existent_file")
        .and_return(exit_code: 1, stdout: "", stderr: "cat: non_existent_file: No such file or directory")

      result = described_class.new(project, "cat non_existent_file").call

      expect(result[:success]).to be false
      expect(result[:exit_code]).to eq(1)
      expect(result[:stderr]).to include("No such file or directory")
    end

    it 'rescues timeout errors' do
      allow(Timeout).to receive(:timeout).with(described_class::COMMAND_TIMEOUT_SECONDS)
        .and_raise(Timeout::Error)

      result = described_class.new(project, "cat large_file").call

      expect(result[:success]).to be false
      expect(result[:exit_code]).to eq(124)
      expect(result[:stderr]).to include("Command timed out")
    end

    it 'rescues SSH unexpected exceptions' do
      allow(ssh_service).to receive(:execute).and_raise(StandardError.new("Connection refused"))

      result = described_class.new(project, "cat README.md").call

      expect(result[:success]).to be false
      expect(result[:exit_code]).to eq(1)
      expect(result[:stderr]).to include("Connection refused")
    end
  end
end
