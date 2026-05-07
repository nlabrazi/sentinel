require 'rails_helper'

RSpec.describe Ping, type: :model do
  it { is_expected.to belong_to(:project) }
  it { is_expected.to validate_inclusion_of(:status).in_array(%w[online offline]) }
  it { is_expected.to validate_presence_of(:checked_at) }
end
