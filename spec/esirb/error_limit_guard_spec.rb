# frozen_string_literal: true

RSpec.describe Esirb::ErrorLimitGuard do
  let(:store) { Faraday::HttpCache::MemoryStore.new }
  let(:now) { Time.utc(2026, 10, 25, 2) }
  let(:state_key) { "esirb:error-limit:https://esi.evetech.net:tranquility" }

  before do
    clock = now
    allow(Time).to receive(:now) { clock }
  end

  # A client on the shared store whose /universe/systems/1 answers each request with the next
  # response, and records the requests it actually sends.
  def client_answering(*responses, **options)
    client = Esirb::Client.new(cache_store: store, retries: 0, **options)
    requests = []
    stub_esi(client).get("/universe/systems/1") do |env|
      requests << env
      responses.shift || json_response({ name: "J-1" })
    end
    [client, requests]
  end

  def with_error_limit(remaining, reset: 30, status: 404, headers: {})
    json_response({ error: "nope" }, status:, headers: {
      "X-ESI-Error-Limit-Remain" => remaining.to_s, "X-ESI-Error-Limit-Reset" => reset.to_s
    }.merge(headers))
  end

  def travel(seconds)
    later = now + seconds
    allow(Time).to receive(:now) { later }
  end

  it "pauses every client on the store once fewer than 20 errors are left", :aggregate_failures do
    first, = client_answering(with_error_limit(19))
    second, requests = client_answering

    expect { first.universe.systems(1).get }.to raise_error(Esirb::NotFound)
    expect { second.universe.systems(1).get }.to raise_error(Esirb::ErrorLimitReached) do |error|
      expect(error.retry_after).to eq 30
      expect(error.message).to include("19 errors left")
    end
    expect(requests).to be_empty
  end

  it "keeps sending with 20 or more left", :aggregate_failures do
    first, = client_answering(with_error_limit(20))
    second, requests = client_answering
    expect { first.universe.systems(1).get }.to raise_error(Esirb::NotFound)
    second.universe.systems(1).get

    expect(requests.size).to eq 1
  end

  it "counts successful responses' error limit too" do
    first, = client_answering(with_error_limit(15, status: 200))
    first.universe.systems(1).get

    expect { client_answering.first.universe.systems(1).get }.to raise_error(Esirb::ErrorLimitReached)
  end

  it "sends again once the window has reset", :aggregate_failures do
    first, = client_answering(with_error_limit(5, reset: 30))
    second, requests = client_answering
    expect { first.universe.systems(1).get }.to raise_error(Esirb::NotFound)
    travel(31)
    second.universe.systems(1).get

    expect(requests.size).to eq 1
  end

  it "pauses for a minute after a 420 without error limit headers", :aggregate_failures do
    first, = client_answering(json_response({ error: "error limited" }, status: 420))
    expect { first.universe.systems(1).get }.to raise_error(Esirb::ErrorLimited)

    expect { client_answering.first.universe.systems(1).get }
      .to raise_error(Esirb::ErrorLimitReached) { |error| expect(error.retry_after).to eq 60 }
  end

  it "leaves the saved state alone for responses without error limit headers", :aggregate_failures do
    first, = client_answering(with_error_limit(50), json_response({ error: "nope" }, status: 404))
    2.times { expect { first.universe.systems(1).get }.to raise_error(Esirb::NotFound) }

    expect(store.read(state_key)["remaining"]).to eq 50
  end

  it "ignores the error limit in a response served from the cache", :aggregate_failures do
    cached = with_error_limit(15, status: 200, reset: 10, headers: { "Cache-Control" => "public, max-age=60" })
    client, requests = client_answering(cached)
    client.universe.systems(1).get # fetched: 15 left, and the window resets in 10 seconds
    travel(11)
    client.universe.systems(1).get # served from the cache, still saying 15 left
    other = Esirb::Client.new(cache_store: store)
    other_requests = stub_endpoint(stub_esi(other), :get, "/status")
    other.status.get

    expect(requests.size).to eq 1
    expect(other_requests.size).to eq 1
  end

  it "keeps separate state for each tenant", :aggregate_failures do
    first, = client_answering(with_error_limit(5))
    expect { first.universe.systems(1).get }.to raise_error(Esirb::NotFound)
    other_tenant, requests = client_answering(tenant: "singularity")
    other_tenant.universe.systems(1).get

    expect(requests.size).to eq 1
  end

  it "does nothing without a cache store", :aggregate_failures do
    first = Esirb::Client.new(retries: 0)
    stub_endpoint(stub_esi(first), :get, "/universe/systems/1", response: with_error_limit(5))
    second = Esirb::Client.new(retries: 0)
    requests = stub_endpoint(stub_esi(second), :get, "/universe/systems/1")
    expect { first.universe.systems(1).get }.to raise_error(Esirb::NotFound)
    second.universe.systems(1).get

    expect(requests.size).to eq 1
  end
end
