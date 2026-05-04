require 'rails_helper'

RSpec.describe JobExecution, type: :model do
  it { is_expected.to belong_to(:cron_job) }
  it { is_expected.to validate_inclusion_of(:status).in_array(%w[success failed]) }
end
