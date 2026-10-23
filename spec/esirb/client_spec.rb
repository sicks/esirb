# frozen_string_literal: true

RSpec.describe Esirb::Client do
  let(:client) { described_class.new }

  describe "#connection" do
    it "is a Faraday::Connection object" do
      expect(client.connection).to be_a Faraday::Connection
    end

    it "includes json request middleware" do
      expect(client.connection.builder.handlers).to include Faraday::Request::Json
    end

    it "includes json response middleware" do
      expect(client.connection.builder.handlers).to include Faraday::Response::Json
    end

    it "does not include http cache middleware without a cache store" do
      expect(client.connection.builder.handlers).not_to include Faraday::HttpCache
    end

    it "includes esirb's error middleware in place of Faraday's", :aggregate_failures do
      expect(client.connection.builder.handlers).to include Esirb::RaiseError
      expect(client.connection.builder.handlers).not_to include Faraday::Response::RaiseError
    end

    it "does not include request authorization" do
      expect(client.connection.builder.handlers).not_to include Faraday::Request::Authorization
    end

    context "with a token" do
      let(:token) { "authentication_token" }
      let(:client) { described_class.new(token:) }

      it "sets the token" do
        expect(client.token).to eq token
      end

      it "includes request authorization via token" do
        expect(client.connection.builder.handlers).to include Faraday::Request::Authorization
      end
    end

    context "with a cache store" do
      let(:client) { described_class.new(cache_store: Faraday::HttpCache::MemoryStore.new) }

      it "includes http cache middleware" do
        expect(client.connection.builder.handlers).to include Faraday::HttpCache
      end
    end

    context "with a configured cache store" do
      before { Esirb.configure { |config| config.cache_store = Faraday::HttpCache::MemoryStore.new } }

      it "includes http cache middleware" do
        expect(client.connection.builder.handlers).to include Faraday::HttpCache
      end

      it "can be turned off for one client with cache_store: nil" do
        expect(described_class.new(cache_store: nil).connection.builder.handlers).not_to include Faraday::HttpCache
      end
    end
  end

  describe "options" do
    it "rejects unknown options" do
      expect { described_class.new(tennant: "singularity") }.to raise_error(ArgumentError, /tennant/)
    end

    it "no longer accepts raise_errors" do
      expect { described_class.new(raise_errors: false) }.to raise_error(ArgumentError, /raise_errors/)
    end
  end

  describe "missing methods" do
    specify "are called on a new Path" do
      expect(client.frank).to be_a Esirb::Path
    end

    it "start a fresh path each time" do
      client.alliances

      expect(client.corporations.string).to eq "/corporations"
    end

    it "reports segment names in respond_to?", :aggregate_failures do
      expect(client).to respond_to(:alliances)
      expect(client).not_to respond_to(:to_ary)
    end

    it "leave other method names to Ruby" do
      expect { client.to_str }.to raise_error(NoMethodError)
    end
  end

  describe "#segment" do
    it "starts a path with a segment exactly as given" do
      expect(client.segment("new-thing", 7).string).to eq "/new-thing/7"
    end
  end

  describe "hyphenated ESI segments" do
    it "are reached with the underscored method name" do
      expect(client.freelance_jobs(7).string).to eq "/freelance-jobs/7"
    end
  end
end
