require 'rails_helper'

RSpec.describe CronJob, type: :model do
  it { is_expected.to belong_to(:project) }
  it { is_expected.to have_many(:job_executions).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:command) }
  it { is_expected.to validate_presence_of(:schedule) }

  it 'validates uniqueness of name within a project' do
    project = create(:project)
    create(:cron_job, project: project, name: 'backup')
    duplicate = build(:cron_job, project: project, name: 'backup')
    expect(duplicate).not_to be_valid
  end
end
