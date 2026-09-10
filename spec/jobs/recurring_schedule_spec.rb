require 'rails_helper'

RSpec.describe 'Recurring schedule configuration', type: :job do
  let(:config_path) { Rails.root.join('config/recurring.yml') }
  let(:raw_config) { YAML.load_file(config_path, aliases: true) }

  it 'defines a valid recurring schedule for production, staging, and development' do
    expect(raw_config).to include('default', 'development', 'staging', 'production')
  end

  it 'schedules HealthcheckAllJob, SyncGithubJob, and CronStatusJob' do
    tasks_config = raw_config['production']

    expect(tasks_config).to include('healthcheck', 'sync_github', 'cron_status')
    expect(tasks_config['healthcheck']['class']).to eq('HealthcheckAllJob')
    expect(tasks_config['healthcheck']['schedule']).to eq('every 1 minute')

    expect(tasks_config['sync_github']['class']).to eq('SyncGithubJob')
    expect(tasks_config['sync_github']['schedule']).to eq('every 5 minutes')

    expect(tasks_config['cron_status']['class']).to eq('CronStatusJob')
    expect(tasks_config['cron_status']['schedule']).to eq('every 5 minutes')
  end

  it 'produces valid SolidQueue recurring tasks with valid cron syntax and existing classes' do
    tasks_config = raw_config['production']

    tasks_config.each do |key, options|
      task = SolidQueue::RecurringTask.from_configuration(key, **options.symbolize_keys)

      expect(task).to be_valid, "Task #{key} is invalid: #{task.errors.full_messages.join(', ')}"
    end
  end
end
