require 'rails_helper'

RSpec.describe CronStatusSyncService, type: :service do
  let(:project) { create(:project) }
  let(:ssh) { instance_double(SshExecutionService) }
  let(:service) { described_class.new(project) }

  before do
    allow(SshExecutionService).to receive(:new).with(project).and_return(ssh)
    allow(Rails.logger).to receive(:error)
  end

  it 'syncs cron jobs from the status.sh JSON contract' do
    allow(ssh).to receive(:execute).with(project.cron_status_command).and_return(
      {
        exit_code: 0,
        stdout: {
          cron_jobs: [
            {
              name: 'daily-import',
              command: './bin/daily-import',
              schedule: '0 2 * * *',
              last_execution_at: '2026-05-06T02:00:12Z',
              last_status: 'success',
              last_duration: 42,
              last_log: 'Import completed'
            }
          ]
        }.to_json,
        stderr: ''
      }
    )

    expect(service.call).to eq(true)

    cron_job = project.cron_jobs.find_by!(name: 'daily-import')
    expect(cron_job.command).to eq('./bin/daily-import')
    expect(cron_job.schedule).to eq('0 2 * * *')
    expect(cron_job.last_execution_at).to eq(Time.zone.parse('2026-05-06T02:00:12Z'))
    expect(cron_job.last_status).to eq('success')
    expect(cron_job.last_duration).to eq(42)
    expect(cron_job.job_executions.count).to eq(1)
    expect(cron_job.job_executions.last.log).to eq('Import completed')
  end

  it 'normalizes ok and failure statuses' do
    allow(ssh).to receive(:execute).and_return(
      {
        exit_code: 0,
        stdout: {
          cron_jobs: [
            { name: 'ok-job', schedule: '* * * * *', last_execution_at: '2026-05-06T02:00:12Z', last_status: 'ok' },
            { name: 'fail-job', schedule: '* * * * *', last_execution_at: '2026-05-06T02:01:12Z', last_status: 'error' }
          ]
        }.to_json,
        stderr: ''
      }
    )

    service.call

    expect(project.cron_jobs.find_by!(name: 'ok-job').last_status).to eq('success')
    expect(project.cron_jobs.find_by!(name: 'fail-job').last_status).to eq('failed')
  end

  it 'does not duplicate the execution history for the same executed_at timestamp' do
    cron_job = create(:cron_job, project: project, name: 'daily-import')
    create(:job_execution, cron_job: cron_job, executed_at: Time.zone.parse('2026-05-06T02:00:12Z'))
    allow(ssh).to receive(:execute).and_return(
      {
        exit_code: 0,
        stdout: {
          cron_jobs: [
            { name: 'daily-import', schedule: '0 2 * * *', last_execution_at: '2026-05-06T02:00:12Z', last_status: 'success' }
          ]
        }.to_json,
        stderr: ''
      }
    )

    expect { service.call }.not_to change(JobExecution, :count)
  end

  it 'supports the previous object-by-job-name payload shape' do
    allow(ssh).to receive(:execute).and_return(
      {
        exit_code: 0,
        stdout: {
          'legacy-backup' => {
            command: './backup',
            schedule: '0 3 * * *',
            last_run: '2026-05-06T03:00:00Z',
            status: 'failed',
            duration: 12,
            log: 'Backup failed'
          }
        }.to_json,
        stderr: ''
      }
    )

    service.call

    cron_job = project.cron_jobs.find_by!(name: 'legacy-backup')
    expect(cron_job.last_status).to eq('failed')
    expect(cron_job.job_executions.last.log).to eq('Backup failed')
  end

  it 'truncates oversized execution logs' do
    allow(ssh).to receive(:execute).and_return(
      {
        exit_code: 0,
        stdout: {
          cron_jobs: [
            {
              name: 'noisy-job',
              schedule: '* * * * *',
              last_execution_at: '2026-05-06T02:00:12Z',
              last_status: 'success',
              last_log: 'o' * (described_class::MAX_LOG_BYTES + 1_000)
            }
          ]
        }.to_json,
        stderr: ''
      }
    )

    service.call

    execution = project.cron_jobs.find_by!(name: 'noisy-job').job_executions.last
    expect(execution.log.bytesize).to eq(described_class::MAX_LOG_BYTES)
    expect(execution.log).to end_with(described_class::TRUNCATED_LOG_NOTICE)
  end

  it 'returns false when SSH command fails' do
    allow(ssh).to receive(:execute).and_return({ exit_code: 1, stdout: '', stderr: 'status.sh missing' })

    expect(service.call).to eq(false)
    expect(project.cron_jobs.count).to eq(0)
  end

  it 'returns false and logs when status.sh returns invalid JSON' do
    allow(ssh).to receive(:execute).and_return({ exit_code: 0, stdout: 'not json', stderr: '' })

    expect(service.call).to eq(false)
    expect(Rails.logger).to have_received(:error).with(/Cron status JSON invalid/)
  end
end
