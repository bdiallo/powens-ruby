# frozen_string_literal: true

require "powens"
require "webmock/rspec"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = "doc" if config.files_to_run.one?

  config.order = :random
  Kernel.srand config.seed

  # Reset configuration before each test
  config.before(:each) do
    Powens.reset_configuration!
  end
end

# Helper to configure Powens for tests
def configure_powens(domain: "test-domain", config_token: "test_config_token",
                     client_id: "test_client_id", client_secret: "test_client_secret")
  Powens.configure do |config|
    config.domain = domain
    config.config_token = config_token
    config.client_id = client_id
    config.client_secret = client_secret
  end
end

# Helper to build the API URL
def api_url(path)
  "https://test-domain.biapi.pro/2.0#{path}"
end

# Helper to stub API requests
def stub_powens_request(method, path, response_body: {}, status: 200, headers: {})
  stub_request(method, api_url(path))
    .to_return(
      status: status,
      body: response_body.to_json,
      headers: { "Content-Type" => "application/json" }.merge(headers)
    )
end
