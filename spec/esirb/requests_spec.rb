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
        "X-Compatibility-Date" => "2026-06-09"
      )
    end

    context "with tenant and language options" do
      let(:client) { Esirb::Client.new(cache: false, tenant: "singularity", language: "de") }

      it "sends them in place of the defaults" do
        requests
        client.status.get

        expect(requests.first.request_headers).to include("X-Tenant" => "singularity", "Accept-Language" => "de")
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
  end

  describe "request body" do
    it "encodes the body as JSON" do
      requests = stub_endpoint(stubs, :post, "/universe/names")
      client.universe.names.post(body: [95_465_499, 30_000_142])

      expect(requests.first.request_headers["Content-Type"]).to eq "application/json"
      expect(requests.first.request_body).to eq "[95465499,30000142]"
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
  end

  # Confirmed bugs from the ESIrb project. Each example fails today, so RSpec reports it as pending.
  # When a fix makes one pass, RSpec fails it and asks for `pending` to be removed.
  describe "known bugs" do
    it "keeps the default headers when per-request headers are passed (MP-207)" do
      pending "MP-207: per-request headers replace the defaults"
      requests = stub_endpoint(stubs, :get, "/status")
      client.status.get(headers: { "X-Custom" => "1" })

      expect(requests.first.request_headers).to include("X-Custom" => "1", "X-Tenant" => "tranquility")
    end

    it "does not send empty conditional headers (MP-209)" do
      pending "MP-209: empty If-Modified-Since / If-None-Match are sent"
      requests = stub_endpoint(stubs, :get, "/status")
      client.status.get

      expect(requests.first.request_headers.keys).not_to include("If-Modified-Since", "If-None-Match")
    end

    it "identifies itself in the User-Agent (MP-210)" do
      pending "MP-210: User-Agent is Faraday's default"
      requests = stub_endpoint(stubs, :get, "/status")
      client.status.get

      expect(requests.first.request_headers["User-Agent"]).to start_with "esirb/"
    end

    it "does not share cached responses between tokens (MP-208)" do
      pending "MP-208: the cache is keyed by URL only"
      store = Faraday::HttpCache::MemoryStore.new
      alice = Esirb::Client.new(token: "alice", cache_store: store)
      bob = Esirb::Client.new(token: "bob", cache_store: store)
      [alice, bob].each do |c|
        stub_endpoint(stub_esi(c), :get, "/characters/1/wallet", response: json_response(
          { owner: c.token }, headers: { "Cache-Control" => "public, max-age=60" }
        ))
      end
      alice.characters(1).wallet.get

      expect(bob.characters(1).wallet.get.body).to eq("owner" => "bob")
    end

    it "raises an Esirb::Error for error statuses (MP-220)" do
      pending "MP-220: Faraday errors are raised as-is"
      stub_endpoint(stubs, :get, "/status", response: json_response({ error: "limited" }, status: 420))

      expect { client.status.get }.to raise_error(Esirb::Error)
    end
  end
end
