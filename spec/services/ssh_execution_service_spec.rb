require 'rails_helper'

RSpec.describe SshExecutionService, type: :service do
  let(:project) { build(:project) }
  let(:service) { described_class.new(project) }

  class FakeSshExitStatus
    def initialize(code)
      @code = code
    end

    def read_long
      @code
    end
  end

  class FakeSshChannel
    attr_reader :command

    def initialize(success:, exit_code:, stdout: '', stderr: '')
      @success = success
      @exit_code = exit_code
      @stdout = stdout
      @stderr = stderr
    end

    def exec(command)
      @command = command
      yield self, @success
      @on_data&.call(self, @stdout)
      @on_extended_data&.call(self, 1, @stderr)
      @on_request&.call(self, FakeSshExitStatus.new(@exit_code))
    end

    def on_data(&block)
      @on_data = block
    end

    def on_extended_data(&block)
      @on_extended_data = block
    end

    def on_request(_name, &block)
      @on_request = block
    end
  end

  class FakeSshSession
    attr_reader :channel

    def initialize(channel)
      @channel = channel
    end

    def open_channel
      yield channel
    end

    def loop; end
  end

  it 'returns stdout, stderr and the remote exit status' do
    channel = FakeSshChannel.new(success: true, exit_code: 42, stdout: 'out', stderr: 'err')
    ssh = FakeSshSession.new(channel)
    allow(Net::SSH).to receive(:start).and_yield(ssh)

    result = service.execute('deploy')

    expect(channel.command).to eq('deploy')
    expect(result).to eq(exit_code: 42, stdout: 'out', stderr: 'err')
  end

  it 'uses explicit SSH security and timeout options' do
    channel = FakeSshChannel.new(success: true, exit_code: 0)
    ssh = FakeSshSession.new(channel)
    allow(Net::SSH).to receive(:start).and_yield(ssh)

    service.execute('deploy')

    expect(Net::SSH).to have_received(:start).with(
      SshExecutionService::VPS_HOST,
      SshExecutionService::SSH_USER,
      hash_including(
        auth_methods: %w[publickey],
        keys: [ SshExecutionService::SSH_KEY_PATH ],
        non_interactive: true,
        timeout: SshExecutionService::CONNECT_TIMEOUT_SECONDS,
        user_known_hosts_file: SshExecutionService::SSH_KNOWN_HOSTS_PATH,
        verify_host_key: :always
      )
    )
  end

  it 'returns a failure when the remote command cannot be opened' do
    channel = FakeSshChannel.new(success: false, exit_code: 0)
    ssh = FakeSshSession.new(channel)
    allow(Net::SSH).to receive(:start).and_yield(ssh)

    result = service.execute('deploy')

    expect(result[:exit_code]).to eq(1)
    expect(result[:stderr]).to include('Could not execute command')
  end

  it 'returns a failure when SSH execution times out' do
    allow(Net::SSH).to receive(:start).and_raise(Timeout::Error, 'execution expired')

    result = service.execute('deploy')

    expect(result).to eq(exit_code: 1, stdout: '', stderr: 'execution expired')
  end
end
