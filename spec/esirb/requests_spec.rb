# frozen_string_literal: true

RSpec.describe "Requests sent to ESI" do
  let(:client) { Esirb::Client.new }
  let(:stubs) { stub_esi(client) }

  describe "URL" do
    it "requests the built path on the ESI host" do
      requests = stub_endpoint(stubs, :get, "/characters/123/location")
      client.characters(123).location.get

      expect(requests.first.url.to_s).to eq "https://esi.evetech.net/characters/123/location"
    end

    context "with a base_url" do
      let(:client) { Esirb::Client.new(base_url: "https://esi.example.test") }

      it "requests that host instead" do
        requests = stub_endpoint(stubs, :get, "/status")
        client.status.get

        expect(requests.first.url.to_s).to eq "https://esi.example.test/status"
      end
    end

    it "sends encoded path params without encoding them twice" do
      requests = stub_endpoint(stubs, :get, "/killmails/1/a%2Fb")
      client.killmails(1, "a/b").get

      expect(requests.first.url.path).to eq "/killmails/1/a%2Fb"
    end

    it "requests hyphenated segments" do
      requests = stub_endpoint(stubs, :get, "/characters/1/freelance-jobs")
      client.characters(1).freelance_jobs.get

      expect(requests.first.url.path).to eq "/characters/1/freelance-jobs"
    end
  end

  describe "headers" do
    let(:requests) { stub_endpoint(stubs, :get, "/status") }

    it "sends the default ESI headers" do
      requests
      client.status.get

      expect(requests.first.request_headers).to include(
        "Accept" => "application/json",
        "Accept-Language" => "en",
        "X-Tenant" => "tranquility",
        "X-Compatibility-Date" => "2026-08-18"
      )
    end

    context "with tenant, language and compatibility_date options" do
      let(:client) do
        Esirb::Client.new(tenant: "singularity", language: "de", compatibility_date: "2026-06-09")
      end

      it "sends them in place of the defaults" do
        requests
        client.status.get

        expect(requests.first.request_headers).to include(
          "X-Tenant" => "singularity", "Accept-Language" => "de", "X-Compatibility-Date" => "2026-06-09"
        )
      end
    end

    context "with nil tenant and language" do
      let(:client) { Esirb::Client.new(tenant: nil, language: nil) }

      it "leaves those headers out" do
        requests
        client.status.get

        expect(requests.first.request_headers.keys)
          .not_to include("X-Tenant", "Accept-Language")
      end
    end

    it "does not send empty conditional headers" do
      requests
      client.status.get

      expect(requests.first.request_headers.keys).not_to include("If-Modified-Since", "If-None-Match")
    end

    it "keeps the defaults when per-request headers are passed" do
      requests
      client.status.get(headers: { "X-Custom" => "1" })

      expect(requests.first.request_headers).to include("X-Custom" => "1", "X-Tenant" => "tranquility")
    end

    it "lets per-request headers override a default, whatever their case" do
      requests
      client.status.get(headers: { "accept-language" => "fr" })

      expect(requests.first.request_headers["Accept-Language"]).to eq "fr"
    end

    it "identifies esirb in the User-Agent" do
      requests
      client.status.get

      expect(requests.first.request_headers["User-Agent"]).to eq "esirb/#{Esirb::VERSION} (+https://github.com/sicks/esirb)"
    end

    context "with a user_agent" do
      let(:client) { Esirb::Client.new(user_agent: "mappy/1.2 (admin@example.com)") }

      it "sends the app's User-Agent followed by esirb's" do
        requests
        client.status.get

        expect(requests.first.request_headers["User-Agent"])
          .to eq "mappy/1.2 (admin@example.com) #{Esirb::Client::USER_AGENT}"
      end
    end

    context "with a blank user_agent" do
      let(:client) { Esirb::Client.new(user_agent: "  ") }

      it "sends esirb's User-Agent alone" do
        requests
        client.status.get

        expect(requests.first.request_headers["User-Agent"]).to eq Esirb::Client::USER_AGENT
      end
    end

    it "sends no Authorization header without a token" do
      requests
      client.status.get

      expect(requests.first.request_headers).not_to have_key("Authorization")
    end

    context "with a token" do
      let(:client) { Esirb::Client.new(token: "abc123") }

      it "sends it as a bearer token" do
        requests
        client.status.get

        expect(requests.first.request_headers["Authorization"]).to eq "Bearer abc123"
      end
    end

    context "with a token callable" do
      let(:tokens) { %w[first second] }
      let(:client) { Esirb::Client.new(token: -> { tokens.shift }) }

      it "asks for the token before every request" do
        requests
        2.times { client.status.get }

        expect(requests.map { |request| request.request_headers["Authorization"] })
          .to eq ["Bearer first", "Bearer second"]
      end
    end

    context "with a token callable that returns nothing" do
      let(:client) { Esirb::Client.new(token: -> {}) }

      it "raises instead of sending an empty token", :aggregate_failures do
        requests

        expect { client.status.get }.to raise_error(Esirb::Error, /token callable returned nil/)
        expect(requests).to be_empty
      end
    end
  end

  describe "connection options" do
    it "sends the timeouts with each request", :aggregate_failures do
      requests = stub_endpoint(stubs, :get, "/status")
      client.status.get

      expect(requests.first.request.timeout).to eq 30
      expect(requests.first.request.open_timeout).to eq 5
    end

    it "lets a client's block replace the adapter" do
      own_stubs = Faraday::Adapter::Test::Stubs.new
      requests = stub_endpoint(own_stubs, :get, "/status")
      client = Esirb::Client.new { |f| f.adapter :test, own_stubs }
      client.status.get

      expect(requests.size).to eq 1
    end

    context "with middleware added by the configured hook" do
      let(:seen) { [] }
      let(:recorder) do
        log = seen
        Class.new(Faraday::Middleware) { define_method(:on_request) { |env| log << env.url.path } }
      end

      before do
        middleware = recorder
        Esirb.configure { |config| config.faraday = ->(f) { f.use middleware } }
      end

      it "runs it for every client's requests" do
        stub_endpoint(stubs, :get, "/status")
        client.status.get

        expect(seen).to eq ["/status"]
      end

      it "runs it inside the cache, so it only sees requests that reach ESI" do
        client = Esirb::Client.new(cache_store: Faraday::HttpCache::MemoryStore.new)
        response = json_response({ players: 1 }, headers: { "Cache-Control" => "public, max-age=60" })
        stub_endpoint(stub_esi(client), :get, "/status", response:)
        2.times { client.status.get }

        expect(seen).to eq ["/status"]
      end
    end
  end

  # The retry rules are in retry_spec.rb; this checks the client uses them.
  describe "retries" do
    it "retries a transient error and returns the response that succeeds" do
      attempts = 0
      stubs.get("/status") do
        attempts += 1
        attempts == 1 ? json_response({ error: "busy" }, status: 503) : json_response({ players: 1 })
      end

      expect(client.status.get.body).to eq("players" => 1)
    end
  end

  describe "sharing a client between threads" do
    it "sends each thread's own request" do
      requests = stub_endpoint(stubs, :get, %r{\A/characters/\d+/location\z})
      10.times.map { |id| Thread.new { client.characters(id).location.get } }.each(&:join)

      expect(requests.map { |request| request.url.path })
        .to match_array(10.times.map { |id| "/characters/#{id}/location" })
    end
  end

  describe "query params" do
    it "sends params as the query string" do
      requests = stub_endpoint(stubs, :get, "/markets/10000002/orders")
      client.markets(10_000_002).orders.get(params: { type_id: 34, page: 2 })

      expect(requests.first.params).to eq("type_id" => "34", "page" => "2")
    end

    it "keeps params alongside headers and a body", :aggregate_failures do
      requests = stub_endpoint(stubs, :post, "/characters/1/contacts")
      client.characters(1).contacts.post(params: { standing: 5.0 }, body: [2], headers: { "X-Custom" => "1" })

      expect(requests.first.params).to eq("standing" => "5.0")
      expect(requests.first.request_headers).to include("X-Custom" => "1", "X-Tenant" => "tranquility")
      expect(requests.first.request_body).to eq "[2]"
    end
  end

  describe "request body" do
    it "encodes the body as JSON", :aggregate_failures do
      requests = stub_endpoint(stubs, :post, "/universe/names")
      client.universe.names.post(body: [95_465_499, 30_000_142])

      expect(requests.first.request_headers["Content-Type"]).to eq "application/json"
      expect(requests.first.request_body).to eq "[95465499,30000142]"
    end

    it "sends a false body instead of dropping it" do
      requests = stub_endpoint(stubs, :put, "/characters/1/settings")
      client.characters(1).settings.put(body: false)

      expect(requests.first.request_body).to eq "false"
    end
  end

  describe "responses" do
    it "parses JSON bodies" do
      stub_endpoint(stubs, :get, "/status", response: json_response({ players: 30_000 }))

      expect(client.status.get.body).to eq("players" => 30_000)
    end

    it "leaves non-JSON bodies as strings" do
      stub_endpoint(stubs, :get, "/status", response: [200, { "Content-Type" => "text/plain" }, "ok"])

      expect(client.status.get.body).to eq "ok"
    end

    it "raises on error statuses" do
      stub_endpoint(stubs, :get, "/characters/1", response: json_response({ error: "not found" }, status: 404))

      expect { client.characters(1).get }.to raise_error(Esirb::NotFound)
    end
  end

  describe "caching" do
    let(:cacheable) { json_response({ players: 1 }, headers: { "Cache-Control" => "public, max-age=60" }) }

    context "with a cache store" do
      let(:store) { Faraday::HttpCache::MemoryStore.new }
      let(:client) { Esirb::Client.new(cache_store: store) }

      it "serves repeat requests from the cache, parsed" do
        requests = stub_endpoint(stubs, :get, "/status", response: cacheable)
        client.status.get

        expect([client.status.get.body, requests.size]).to eq [{ "players" => 1 }, 1]
      end

      it "stores the raw body as JSON rather than Marshal data" do
        stub_endpoint(stubs, :get, "/status", response: cacheable)
        client.status.get
        # ByVary also writes an index entry holding the Vary header names; this picks the response.
        entry = store.instance_variable_get(:@cache).values.find { |value| value.start_with?("{") }

        expect(JSON.parse(entry)["body"]).to eq '{"players":1}'
      end
    end

    context "with a cache store set in Esirb.configure" do
      before { Esirb.configure { |config| config.cache_store = Faraday::HttpCache::MemoryStore.new } }

      it "shares the cache between new clients" do
        first = Esirb::Client.new
        second = Esirb::Client.new
        stub_endpoint(stub_esi(first), :get, "/status", response: cacheable)
        requests = stub_endpoint(stub_esi(second), :get, "/status", response: cacheable)
        first.status.get
        second.status.get

        expect(requests).to be_empty
      end
    end

    context "with private responses" do
      let(:store) { Faraday::HttpCache::MemoryStore.new }
      # What ESI sends for authenticated endpoints.
      let(:private_headers) do
        { "Cache-Control" => "private, max-age=5, must-revalidate, stale-if-error=900",
          "Vary" => "X-Tenant, Accept-Language, X-Compatibility-Date" }
      end

      def private_client(owner, **options)
        client = Esirb::Client.new(cache_store: store, **options)
        response = json_response({ owner: }, headers: private_headers)
        [client, stub_endpoint(stub_esi(client), :get, "/characters/1/location", response:)]
      end

      it "serves them from the cache to the same token" do
        first, = private_client("alice", token: "alice")
        second, requests = private_client("alice", token: "alice")
        first.characters(1).location.get
        second.characters(1).location.get

        expect(requests).to be_empty
      end

      it "doesn't serve them to another token" do
        alice, = private_client("alice", token: "alice")
        bob, = private_client("bob", token: "bob")
        alice.characters(1).location.get

        expect(bob.characters(1).location.get.body).to eq("owner" => "bob")
      end

      it "doesn't serve them to a client without a token" do
        alice, = private_client("alice", token: "alice")
        anonymous, = private_client("anonymous")
        alice.characters(1).location.get

        expect(anonymous.characters(1).location.get.body).to eq("owner" => "anonymous")
      end
    end

    context "with a stale entry" do
      let(:client) { Esirb::Client.new(cache_store: Faraday::HttpCache::MemoryStore.new, token: "alice") }

      it "revalidates with the ETag and serves the cached body on a 304", :aggregate_failures do
        conditional = []
        stubs.get("/characters/1/location") do |env|
          conditional << env.request_headers["If-None-Match"]
          next [304, { "ETag" => '"v1"' }, ""] if env.request_headers["If-None-Match"]

          json_response({ solar_system_id: 30_000_142 },
                        headers: { "Cache-Control" => "private, max-age=0, must-revalidate", "ETag" => '"v1"' })
        end
        client.characters(1).location.get

        expect(client.characters(1).location.get.body).to eq("solar_system_id" => 30_000_142)
        expect(conditional).to eq [nil, '"v1"']
      end
    end

    context "without a cache store" do
      it "sends every request" do
        requests = stub_endpoint(stubs, :get, "/status", response: cacheable)
        2.times { client.status.get }

        expect(requests.size).to eq 2
      end
    end

    context "with a store shared between clients" do
      let(:store) { Faraday::HttpCache::MemoryStore.new }
      # The Vary header ESI sends, including its repeated Accept-Language.
      let(:esi_cache_headers) do
        { "Cache-Control" => "public, max-age=60",
          "Vary" => "X-Tenant, Accept-Language, X-Compatibility-Date, Accept-Language" }
      end

      # Builds a client on the shared store. Its wallet endpoint answers with `owner` and records requests.
      def cached_client(owner, **options)
        client = Esirb::Client.new(cache_store: store, **options)
        response = json_response({ owner: }, headers: esi_cache_headers)
        [client, stub_endpoint(stub_esi(client), :get, "/characters/1/wallet", response:)]
      end

      it "doesn't serve one token's response to another token" do
        alice, = cached_client("alice", token: "alice")
        bob, = cached_client("bob", token: "bob")
        alice.characters(1).wallet.get

        expect(bob.characters(1).wallet.get.body).to eq("owner" => "bob")
      end

      it "keys entries by the token a callable returns at the time" do
        tokens = %w[alice bob]
        client = Esirb::Client.new(cache_store: store, token: -> { tokens.shift })
        stub_esi(client).get("/characters/1/wallet") do |env|
          json_response({ owner: env.request_headers["Authorization"] }, headers: esi_cache_headers)
        end
        client.characters(1).wallet.get

        expect(client.characters(1).wallet.get.body).to eq("owner" => "Bearer bob")
      end

      it "shares responses between clients with the same token" do
        first, = cached_client("alice", token: "alice")
        second, requests = cached_client("alice", token: "alice")
        first.characters(1).wallet.get
        second.characters(1).wallet.get

        expect(requests).to be_empty
      end

      it "doesn't serve a token's response to a client without one" do
        alice, = cached_client("alice", token: "alice")
        anonymous, = cached_client("anonymous")
        alice.characters(1).wallet.get

        expect(anonymous.characters(1).wallet.get.body).to eq("owner" => "anonymous")
      end

      { language: %w[en de], tenant: %w[tranquility singularity], compatibility_date: %w[2026-08-18 2026-06-09] }
        .each do |option, (first_value, second_value)|
        it "keeps separate entries for each #{option}" do
          first, = cached_client(first_value, option => first_value)
          second, = cached_client(second_value, option => second_value)
          first.characters(1).wallet.get

          expect(second.characters(1).wallet.get.body).to eq("owner" => second_value)
        end
      end

      it "keeps separate entries for a per-request Accept-Language" do
        client, requests = cached_client("alice")
        client.characters(1).wallet.get
        client.characters(1).wallet.get(headers: { "Accept-Language" => "fr" })

        expect(requests.size).to eq 2
      end
    end
  end
end
