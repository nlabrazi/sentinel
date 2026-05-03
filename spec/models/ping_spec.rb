require 'rails_helper'

RSpec.describe Ping, type: :model do
  it "est valide avec un nom" do
    ping = Ping.new(name: "test")
    expect(ping).to be_valid
  end
end
