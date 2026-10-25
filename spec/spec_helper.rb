# frozen_string_literal: true

require "esirb"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.include EsiStubs

  config.after { Esirb.reset_configuration! }

  # Retries still happen in specs, just without waiting between attempts.
  config.before { allow(Esirb::Retry).to receive(:pause) }

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
