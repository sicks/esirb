# frozen_string_literal: true

RSpec.describe "Requests sent to ESI" do
  let(:client) { Esirb::Client.new(cache: false) }
  let(:stubs) { stub_esi(client) }

  describe "URL" do
    it "requests the built path on the ESI host" do
      requests = stub_endpoint(stubs, :get, "/characters/123/location")
      client.characters(123).location.get

      expect(requests.first.url.to_s).to eq "https://esi.evetech.net/characters/123/location"
    end

    context "with a base_url" do
      let(:client) { Esirb::Client.new(cache: false, base_url: "https://esi.example.test") }

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
        Esirb::Client.new(cache: false, tenant: "singularity", language: "de", compatibility_date: "2026-06-09")
      end

      it "sends them in place of the defaults" do
        requests
        client.status.get

        expect(requests.first.request_headers).to include(
          "X-Tenant" => "singularity", "Accept-Language" => "de", "X-Compatibility-Date" => "2026-06-09"
        )
      end
    end

    context "with nil tenant, language and compatibility_date" do
      let(:client) { Esirb::Client.new(cache: false, tenant: nil, language: nil, compatibility_date: nil) }

      it "leaves those headers out" do
        requests
        client.status.get

        expect(requests.first.request_headers.keys)
          .not_to include("X-Tenant", "Accept-Language", "X-Compatibility-Date")
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
      let(:client) { Esirb::Client.new(cache: false, user_agent: "mappy/1.2 (admin@example.com)") }

      it "sends the app's User-Agent followed by esirb's" do
        requests
        client.status.get

        expect(requests.first.request_headers["User-Agent"])
          .to eq "mappy/1.2 (admin@example.com) #{Esirb::Client::USER_AGENT}"
      end
    end

    context "with a blank user_agent" do
      let(:client) { Esirb::Client.new(cache: false, user_agent: "  ") }

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
      let(:client) { Esirb::Client.new(cache: false, token: "abc123") }

      it "sends it as a bearer token" do
        requests
        client.status.get

        expect(requests.first.request_headers["Authorization"]).to eq "Bearer abc123"
      end
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

      expect { client.characters(1).get }.to raise_error(Faraday::ResourceNotFound)
    end

    context "with raise_errors: false" do
      let(:client) { Esirb::Client.new(cache: false, raise_errors: false) }

      it "returns error responses" do
        stub_endpoint(stubs, :get, "/characters/1", response: json_response({ error: "not found" }, status: 404))
        response = client.characters(1).get

        expect([response.status, response.body]).to eq [404, { "error" => "not found" }]
      end
    end
  end

  describe "caching" do
    let(:cacheable) { json_response({ players: 1 }, headers: { "Cache-Control" => "public, max-age=60" }) }

    context "with a cache store" do
      let(:client) { Esirb::Client.new(cache_store: Faraday::HttpCache::MemoryStore.new) }

      it "serves repeat requests from the cache" do
        requests = stub_endpoint(stubs, :get, "/status", response: cacheable)
        2.times { client.status.get }

        expect(requests.size).to eq 1
      end
    end

    context "with cache: false" do
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

  # Confirmed bugs from the ESIrb project. Each example fails today, so RSpec reports it as pending.
  # When a fix makes one pass, RSpec fails it and asks for `pending` to be removed.
  describe "known bugs" do
    it "raises an Esirb::Error for error statuses (MP-220)" do
      pending "MP-220: Faraday errors are raised as-is"
      stub_endpoint(stubs, :get, "/status", response: json_response({ error: "limited" }, status: 420))

      expect { client.status.get }.to raise_error(Esirb::Error)
    end
  end
end
