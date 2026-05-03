require 'rails_helper'

RSpec.describe Project, type: :model do
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

  describe '#deploy_command' do
    it 'returns the correct shell command' do
      project = build(:project, vps_path: '/srv/projects/myapp')
      expect(project.deploy_command).to eq("bash -lc 'cd /srv/projects/myapp && ./deploy.sh'")
    end
  end

  describe '#cron_status_command' do
    it 'returns the correct shell command' do
      project = build(:project, vps_path: '/srv/projects/myapp')
      expect(project.cron_status_command).to eq("bash -lc 'cd /srv/projects/myapp && ./status.sh'")
    end
  end
end
