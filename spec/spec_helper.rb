# frozen_string_literal: true

require "esirb"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.include EsiStubs

  config.after { Esirb.reset_configuration! }

  # Retries still happen in specs, just without waiting between attempts.
  config.before do
    stub_const("Esirb::Client::RETRY_OPTIONS", Esirb::Client::RETRY_OPTIONS.merge(interval: 0, interval_randomness: 0))
  end

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
