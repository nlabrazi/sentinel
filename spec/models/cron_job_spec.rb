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

  describe "cron monitoring" do
    include ActiveSupport::Testing::TimeHelpers

    let(:now) { Time.utc(2026, 9, 30, 6, 30) }
    let(:job) { build(:cron_job, schedule: "15 0,6,12,18 * * *", last_execution_at: Time.utc(2026, 9, 30, 0, 15)) }

    before { stub_const("CronJob::OVERDUE_GRACE", 15.minutes) }

    it "keeps a missed occurrence within its grace period healthy" do
      expect(job.overdue?(at: now - 10.minutes)).to be(false)
      expect(job.overdue?(at: now - 0.001)).to be(false)
    end

    it "detects a missed occurrence exactly at and after the grace boundary" do
      expect(job.overdue?(at: now)).to be(true)
      expect(job.overdue?(at: now + 1.minute)).to be(true)
      expect(job.needs_attention?(at: now)).to be(true)
      travel_to(now) { expect(job.display_status).to eq("overdue") }
    end

    it "accepts an execution at or after the expected occurrence" do
      job.last_execution_at = now - 15.minutes
      expect(job.overdue?(at: now)).to be(false)
      job.last_execution_at += 12.seconds
      expect(job.overdue?(at: now)).to be(false)
    end

    it "uses the daily schedule instead of a fixed execution age" do
      job.schedule = "0 2 * * *"
      job.last_execution_at = Time.utc(2026, 9, 29, 2)
      expect(job.overdue?(at: Time.utc(2026, 9, 30, 2, 14))).to be(false)
      expect(job.overdue?(at: Time.utc(2026, 9, 30, 2, 15))).to be(true)
    end

    it "supports weekly schedules" do
      job.schedule = "0 2 * * 1"
      job.last_execution_at = Time.utc(2026, 9, 28, 2)
      expect(job.overdue?(at: now)).to be(false)
      expect(job.overdue?(at: Time.utc(2026, 10, 5, 2, 15))).to be(true)
    end

    it "interprets schedules in UTC even when Rails uses another timezone" do
      Time.use_zone("America/New_York") do
        expect(job.overdue?(at: now.in_time_zone)).to be(true)
        expect(job.overdue?(at: (now - 1.minute).in_time_zone)).to be(false)
      end
    end

    it "keeps never-run jobs separate" do
      job.last_execution_at = nil
      expect(job.overdue?(at: now)).to be(false)
      expect(job.display_status).to eq("never run")
      expect(job.needs_attention?(at: now)).to be(true)
    end

    it "treats invalid and impossible schedules as unknown without raising" do
      [ "invalid", "0 0 30 2 *", "", nil ].each do |schedule|
        job.schedule = schedule
        expect(job.overdue?(at: now)).to be(false)
        expect(job.display_status).to eq("unknown")
        expect(job.needs_attention?(at: now)).to be(true)
      end
    end

    it "keeps a failed execution failed even when overdue" do
      job.last_status = "failed"
      travel_to(now) do
        expect(job.overdue?).to be(true)
        expect(job.display_status).to eq("failed")
      end
    end
  end
end
