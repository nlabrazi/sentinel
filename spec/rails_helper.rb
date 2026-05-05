# spec/rails_helper.rb
require 'webmock/rspec'
require 'spec_helper'
ENV['RAILS_ENV'] = 'test'
ENV['GITHUB_TOKEN'] ||= 'test-token'
require File.expand_path('../config/environment', __dir__)
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'

# Shoulda Matchers configuration
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

RSpec.configure do |config|
  # Factory Bot syntactic sugar
  config.include FactoryBot::Syntax::Methods
  config.include Devise::Test::IntegrationHelpers, type: :request

  # Remove this line if you're not using ActiveRecord
  config.fixture_paths = [Rails.root.join('spec/fixtures')]

  # If you're not using transactional fixtures, add `config.use_transactional_fixtures = true`
  config.use_transactional_fixtures = true

  # RSpec Rails can automatically mix in different behaviours to your tests
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
end
