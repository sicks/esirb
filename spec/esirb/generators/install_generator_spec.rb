# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "rails"
require "generators/esirb/install/install_generator"

RSpec.describe Esirb::Generators::InstallGenerator do
  let(:destination) { Dir.mktmpdir }
  let(:initializer) { File.join(destination, "config/initializers/esirb.rb") }

  after { FileUtils.rm_rf(destination) }

  def generate
    described_class.start([], destination_root: destination)
  end

  it "writes config/initializers/esirb.rb" do
    expect { generate }.to output(%r{create\s+config/initializers/esirb\.rb}).to_stdout
  end

  context "when it has been generated" do
    before do
      allow($stdout).to receive(:write)
      generate
    end

    it "configures esirb when loaded", :aggregate_failures do
      load initializer

      expect(Esirb.configuration.user_agent).to eq "my-app/1.0 (you@example.com)"
      expect(Esirb.configuration.compatibility_date).to eq Esirb::Configuration::DEFAULTS[:compatibility_date]
      expect { Esirb::Client.new }.not_to raise_error
    end

    it "shows the other options with esirb's defaults, commented out", :aggregate_failures do
      contents = File.read(initializer)

      expect(contents).to include("# config.timeout = 30", "# config.open_timeout = 5", "# config.retries = 2")
      expect(contents).to include('# config.tenant = "tranquility"', '# config.language = "en"')
    end
  end

  it "names the User-Agent after the Rails app" do
    stub_const("MappyTest::Application", Class.new)
    allow(Rails).to receive(:application).and_return(MappyTest::Application.new)
    allow($stdout).to receive(:write)
    generate

    expect(File.read(initializer)).to include('config.user_agent = "mappy-test/1.0 (you@example.com)"')
  end
end
