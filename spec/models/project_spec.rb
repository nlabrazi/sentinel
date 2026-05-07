require 'rails_helper'
require 'stringio'

RSpec.describe Project, type: :model do
  around do |example|
    original_access_key = ENV['APIFLASH_ACCESS_KEY']
    example.run
  ensure
    ENV['APIFLASH_ACCESS_KEY'] = original_access_key
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:slug) }
    it { is_expected.to validate_uniqueness_of(:slug) }
    it { is_expected.to validate_presence_of(:repo_url) }
    it { is_expected.to validate_presence_of(:branch) }
    it { is_expected.to validate_presence_of(:production_url) }
    it { is_expected.to validate_presence_of(:vps_path) }
    it { is_expected.to define_enum_for(:status).with_values(online: 0, offline: 1, unknown: 2).backed_by_column_of_type(:integer) }
  end

  describe 'associations' do
    it { is_expected.to have_many(:deployments).dependent(:destroy) }
    it { is_expected.to have_many(:cron_jobs).dependent(:destroy) }
  end

  describe '#github_repo' do
    it 'extracts user/repo from a GitHub HTTPS URL' do
      project = build(:project, repo_url: 'https://github.com/nlabrazi/argandici.git')
      expect(project.github_repo).to eq('nlabrazi/argandici')
    end

    it 'works without .git suffix' do
      project = build(:project, repo_url: 'https://github.com/nlabrazi/argandici')
      expect(project.github_repo).to eq('nlabrazi/argandici')
    end
  end

  describe 'URL safety' do
    it 'accepts HTTPS GitHub repository URLs' do
      project = build(:project, repo_url: 'https://github.com/nlabrazi/argandici.git')

      expect(project).to be_valid
    end

    it 'rejects non-GitHub repository URLs' do
      project = build(:project, repo_url: 'https://gitlab.com/nlabrazi/argandici.git')

      expect(project).not_to be_valid
      expect(project.errors[:repo_url]).to be_present
    end

    it 'rejects SSH repository URLs' do
      project = build(:project, repo_url: 'git@github.com:nlabrazi/argandici.git')

      expect(project).not_to be_valid
      expect(project.errors[:repo_url]).to be_present
    end

    it 'accepts HTTP and HTTPS production URLs' do
      https_project = build(:project, production_url: 'https://argandici.com')
      http_project = build(:project, production_url: 'http://argandici.test')

      expect(https_project).to be_valid
      expect(http_project).to be_valid
    end

    it 'rejects production URLs without a HTTP scheme' do
      project = build(:project, production_url: 'javascript:alert(1)')

      expect(project).not_to be_valid
      expect(project.errors[:production_url]).to be_present
    end

    it 'rejects production URLs with embedded credentials' do
      project = build(:project, production_url: 'https://user:pass@example.com')

      expect(project).not_to be_valid
      expect(project.errors[:production_url]).to be_present
    end
  end

  describe '#deploy_command' do
    it 'returns the correct shell command' do
      project = build(:project, vps_path: '/srv/apps/myapp')
      expect(project.deploy_command).to eq('bash -lc cd\ /srv/apps/myapp\ \&\&\ ./deploy.sh')
    end

    it 'escapes the VPS path before interpolating it into the shell command' do
      project = build(:project, vps_path: '/srv/apps/my app')

      expect(Shellwords.split(project.deploy_command)).to eq([
        'bash',
        '-lc',
        'cd /srv/apps/my\ app && ./deploy.sh'
      ])
    end
  end

  describe '#cron_status_command' do
    it 'returns the correct shell command' do
      project = build(:project, vps_path: '/srv/apps/myapp')
      expect(project.cron_status_command).to eq('bash -lc cd\ /srv/apps/myapp\ \&\&\ ./status.sh')
    end
  end

  describe '#cron_summary_status' do
    it 'returns unknown when no cron job is configured' do
      project = create(:project)

      expect(project.cron_summary_status).to eq('unknown')
    end

    it 'returns ok when all cron jobs succeeded' do
      project = create(:project)
      create(:cron_job, project: project, last_status: 'success')
      create(:cron_job, project: project, name: 'Other job', last_status: 'success')

      expect(project.cron_summary_status).to eq('ok')
    end

    it 'returns failed when at least one cron job failed' do
      project = create(:project)
      create(:cron_job, project: project, last_status: 'success')
      create(:cron_job, project: project, name: 'Failing job', last_status: 'failed')

      expect(project.cron_summary_status).to eq('failed')
    end
  end

  describe '#maintenance_command' do
    it 'builds the activation command with an escaped flag path' do
      project = build(:project, vps_path: '/srv/apps/myapp')

      expect(project.maintenance_command(true)).to eq('bash -lc touch\ /srv/apps/myapp/maintenance.on')
    end

    it 'builds the deactivation command with an escaped flag path' do
      project = build(:project, vps_path: '/srv/apps/myapp')

      expect(project.maintenance_command(false)).to eq('bash -lc rm\ -f\ /srv/apps/myapp/maintenance.on')
    end
  end

  describe 'vps_path safety' do
    it 'rejects paths outside /srv/apps' do
      project = build(:project, vps_path: '/tmp/myapp')

      expect(project).not_to be_valid
      expect(project.errors[:vps_path]).to be_present
    end

    it 'rejects shell metacharacters' do
      project = build(:project, vps_path: '/srv/apps/myapp; rm -rf /')

      expect(project).not_to be_valid
      expect(project.errors[:vps_path]).to be_present
    end

    it 'rejects path traversal' do
      project = build(:project, vps_path: '/srv/apps/../secrets')

      expect(project).not_to be_valid
      expect(project.errors[:vps_path]).to be_present
    end
  end

  describe '#regenerate_screenshot!' do
    it 'does not call ApiFlash when no access key is configured' do
      ENV['APIFLASH_ACCESS_KEY'] = nil
      project = build(:project)

      expect(URI).not_to receive(:open)

      expect(project.regenerate_screenshot!).to eq(false)
    end

    it 'downloads screenshots with explicit network timeouts' do
      ENV['APIFLASH_ACCESS_KEY'] = 'test-key'
      project = build(:project, slug: 'myapp')
      screenshot = instance_double(ActiveStorage::Attached::One, attached?: false)
      image_io = StringIO.new('jpeg')

      allow(project).to receive(:screenshot).and_return(screenshot)
      allow(screenshot).to receive(:attach)

      expect(URI).to receive(:open)
        .with(
          project.fresh_screenshot_url,
          open_timeout: Project::SCREENSHOT_OPEN_TIMEOUT,
          read_timeout: Project::SCREENSHOT_READ_TIMEOUT
        )
        .and_yield(image_io)

      expect(project.regenerate_screenshot!).to eq(true)
      expect(screenshot).to have_received(:attach).with(
        io: image_io,
        filename: 'myapp.jpg',
        content_type: 'image/jpeg'
      )
    end

    it 'returns false when the screenshot request times out' do
      ENV['APIFLASH_ACCESS_KEY'] = 'test-key'
      project = build(:project)

      allow(URI).to receive(:open).and_raise(Net::ReadTimeout)

      expect(project.regenerate_screenshot!).to eq(false)
    end
  end

  describe '#latest_ping' do
    it 'returns the newest runtime check' do
      project = create(:project)
      old_ping = create(:ping, project: project, checked_at: 2.hours.ago)
      new_ping = create(:ping, project: project, checked_at: 5.minutes.ago)

      expect(project.latest_ping).to eq(new_ping)
      expect(project.latest_ping).not_to eq(old_ping)
    end
  end
end
