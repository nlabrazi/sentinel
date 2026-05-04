require 'rails_helper'

RSpec.describe Deployment, type: :model do
  it { is_expected.to belong_to(:project) }
  it { is_expected.to validate_presence_of(:commit_sha) }
  it { is_expected.to define_enum_for(:status).with_values(pending: 0, running: 1, success: 2, failed: 3).backed_by_column_of_type(:integer) }
end
