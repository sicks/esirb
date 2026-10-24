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

  describe "timeouts" do
    it "defaults to 30 seconds for a response and 5 to connect", :aggregate_failures do
      expect(client.connection.options.timeout).to eq 30
      expect(client.connection.options.open_timeout).to eq 5
    end

    it "uses configured timeouts, overridden per client", :aggregate_failures do
      Esirb.configure { |config| config.timeout = 10 }
      client = described_class.new(open_timeout: 2)

      expect(client.connection.options.timeout).to eq 10
      expect(client.connection.options.open_timeout).to eq 2
    end

    it "leaves a nil timeout to the adapter" do
      expect(described_class.new(timeout: nil).connection.options.timeout).to be_nil
    end
  end

  describe "faraday hooks" do
    it "calls the configured hook, then the client's block, with the connection builder" do
      calls = []
      Esirb.configure { |config| config.faraday = ->(builder) { calls << [:configured, builder.class] } }
      described_class.new { |builder| calls << [:block, builder.class] }

      expect(calls).to eq [[:configured, Faraday::Connection], [:block, Faraday::Connection]]
    end

    it "lets a client's faraday option replace the configured hook" do
      calls = []
      Esirb.configure { |config| config.faraday = ->(_) { calls << :configured } }
      described_class.new(faraday: ->(_) { calls << :client })

      expect(calls).to eq [:client]
    end

    it "rejects a retries option that isn't a whole number of 0 or more" do
      expect { described_class.new(retries: -1) }.to raise_error(ArgumentError, /retries must be/)
    end

    it "rejects a faraday option that isn't callable" do
      expect { described_class.new(faraday: "logger") }.to raise_error(ArgumentError, /faraday must be/)
    end
  end

  describe "state" do
    it "builds its connection when it's created" do
      expect(client.instance_variable_get(:@connection)).to be_a Faraday::Connection
    end

    it "keeps no state from building paths" do
      snapshot = -> { client.instance_variables.to_h { |name| [name, client.instance_variable_get(name)] } }

      expect { client.characters(1).location }.not_to(change(&snapshot))
    end

    it "no longer remembers the last path; `path` is just a segment" do
      client.alliances

      expect(client.path.string).to eq "/path"
    end
  end

  describe "options" do
    it "rejects unknown options" do
      expect { described_class.new(tennant: "singularity") }.to raise_error(ArgumentError, /tennant/)
    end

    it "accepts a callable token and returns it as given" do
      token = -> { "abc123" }

      expect(described_class.new(token:).token).to equal token
    end

    it "rejects a token that is neither a string nor callable" do
      expect { described_class.new(token: 123) }.to raise_error(ArgumentError, /token must be a string/)
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
