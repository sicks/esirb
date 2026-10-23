# frozen_string_literal: true

RSpec.describe Esirb::Configuration do
  describe "defaults" do
    subject(:config) { described_class.new }

    it "matches ESI's production settings" do
      expect(config.to_h).to eq(
        base_url: "https://esi.evetech.net",
        compatibility_date: "2026-08-18",
        tenant: "tranquility",
        language: "en",
        user_agent: nil,
        raise_errors: true,
        cache_store: nil
      )
    end
  end

  describe "Esirb.configure" do
    it "changes the defaults for new clients", :aggregate_failures do
      Esirb.configure do |config|
        config.base_url = "https://esi.example.test"
        config.compatibility_date = "2026-06-09"
        config.tenant = "singularity"
        config.language = "de"
        config.user_agent = "mappy/1.2 (admin@example.com)"
        config.raise_errors = false
      end
      client = Esirb::Client.new

      expect([client.base_url, client.compatibility_date, client.tenant, client.language, client.raise_errors])
        .to eq ["https://esi.example.test", "2026-06-09", "singularity", "de", false]
      expect(client.user_agent).to eq "mappy/1.2 (admin@example.com) #{Esirb::Client::USER_AGENT}"
    end

    it "is overridden by options passed to a client" do
      Esirb.configure { |config| config.tenant = "singularity" }

      expect(Esirb::Client.new(tenant: "tranquility").tenant).to eq "tranquility"
    end

    it "doesn't change clients that already exist" do
      client = Esirb::Client.new
      Esirb.configure { |config| config.language = "fr" }

      expect(client.language).to eq "en"
    end
  end

  describe "Esirb.reset_configuration!" do
    it "restores the defaults" do
      Esirb.configure { |config| config.tenant = "singularity" }
      Esirb.reset_configuration!

      expect(Esirb.configuration.tenant).to eq "tranquility"
    end
  end
end
