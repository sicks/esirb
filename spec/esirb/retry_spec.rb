# frozen_string_literal: true

RSpec.describe Esirb::Retry do
  let(:client) { Esirb::Client.new }
  let(:stubs) { stub_esi(client) }

  let(:attempts) { [] }
  let(:ok) { json_response({ players: 1 }) }

  def busy(retry_after:)
    json_response({ error: "busy" }, status: 503, headers: { "Retry-After" => retry_after })
  end

  # Answers each attempt at `path` with the next item: a status (as an error response), an
  # exception class to raise, or a full response.
  def respond_in_turn(verb, path, *answers)
    stubs.public_send(verb, path) do |env|
      attempts << env
      answer = answers.shift || ok
      raise answer, "boom" if answer.is_a?(Class)

      answer.is_a?(Integer) ? json_response({ error: "busy" }, status: answer) : answer
    end
  end

  { 502 => Esirb::BadGateway, 503 => Esirb::ServiceUnavailable, 504 => Esirb::GatewayTimeout }.each do |status, error|
    it "retries a #{status} and returns the response that succeeds", :aggregate_failures do
      respond_in_turn(:get, "/status", status, status)

      expect(client.status.get.body).to eq("players" => 1)
      expect(attempts.size).to eq 3
    end

    it "raises #{error} after the last retry", :aggregate_failures do
      respond_in_turn(:get, "/status", status, status, status)

      expect { client.status.get }.to raise_error(error)
      expect(attempts.size).to eq 3
    end
  end

  { Faraday::TimeoutError => "a timeout", Faraday::ConnectionFailed => "a connection failure" }.each do |raised, name|
    it "retries #{name}", :aggregate_failures do
      respond_in_turn(:get, "/status", raised)

      expect(client.status.get.body).to eq("players" => 1)
      expect(attempts.size).to eq 2
    end
  end

  [500, 404, 420].each do |status|
    it "doesn't retry a #{status}", :aggregate_failures do
      respond_in_turn(:get, "/status", status)

      expect { client.status.get }.to raise_error(Esirb::ResponseError)
      expect(attempts.size).to eq 1
    end
  end

  it "retries PUT and DELETE, which are safe to repeat" do
    respond_in_turn(:put, "/characters/1/settings", 503)
    respond_in_turn(:delete, "/characters/1/settings", 503)
    client.characters(1).settings.put(body: [1])
    client.characters(1).settings.delete

    expect(attempts.size).to eq 4
  end

  it "doesn't retry POST, which might not be safe to repeat", :aggregate_failures do
    respond_in_turn(:post, "/characters/1/contacts", 503)

    expect { client.characters(1).contacts.post(body: [2]) }.to raise_error(Esirb::ServiceUnavailable)
    expect(attempts.size).to eq 1
  end

  it "waits as long as ESI's Retry-After asks" do
    respond_in_turn(:get, "/status", busy(retry_after: "0.2"))
    client.status.get

    expect(described_class).to have_received(:pause).with(0.2)
  end

  it "backs off about 0.5s, then 1s, without a Retry-After" do
    respond_in_turn(:get, "/status", 503, 503)
    waits = []
    allow(described_class).to receive(:pause) { |seconds| waits << seconds }
    client.status.get

    expect(waits).to match [be_between(0.5, 0.75), be_between(1, 1.5)]
  end

  it "counts every retry against one limit, whatever the reason", :aggregate_failures do
    slow_down = json_response({ error: "slow" }, status: 429, headers: { "Retry-After" => "1" })
    respond_in_turn(:get, "/status", 503, slow_down, 503)

    expect { client.status.get }.to raise_error(Esirb::ServiceUnavailable)
    expect(attempts.size).to eq 3
  end

  it "raises straight away when Retry-After asks for longer than 10 seconds", :aggregate_failures do
    respond_in_turn(:get, "/status", busy(retry_after: "60"))

    expect { client.status.get }.to raise_error(Esirb::ServiceUnavailable)
    expect(attempts.size).to eq 1
  end

  context "when ESI's error limit is nearly used up" do
    def busy_with_errors_left(count)
      json_response({ error: "busy" }, status: 503, headers: { "X-ESI-Error-Limit-Remain" => count.to_s })
    end

    it "doesn't retry with fewer than 20 errors left", :aggregate_failures do
      respond_in_turn(:get, "/status", busy_with_errors_left(19))

      expect { client.status.get }.to raise_error(Esirb::ServiceUnavailable)
      expect(attempts.size).to eq 1
    end

    it "still retries with 20 or more left", :aggregate_failures do
      respond_in_turn(:get, "/status", busy_with_errors_left(20))

      expect(client.status.get.body).to eq("players" => 1)
      expect(attempts.size).to eq 2
    end
  end

  describe "429 Too Many Requests" do
    def too_many(retry_after: nil)
      json_response({ error: "slow down" }, status: 429, headers: { "Retry-After" => retry_after }.compact)
    end

    it "waits for a short Retry-After, then retries", :aggregate_failures do
      respond_in_turn(:get, "/characters/1/location", too_many(retry_after: "3"))

      expect(client.characters(1).location.get.body).to eq("players" => 1)
      expect(described_class).to have_received(:pause).with(3.0)
      expect(attempts.size).to eq 2
    end

    it "raises straight away when Retry-After is over 10 seconds", :aggregate_failures do
      respond_in_turn(:get, "/characters/1/location", too_many(retry_after: "60"))

      expect { client.characters(1).location.get }.to raise_error(Esirb::TooManyRequests) do |error|
        expect(error.retry_after).to eq 60
      end
      expect(attempts.size).to eq 1
    end

    it "raises straight away without Retry-After, which EVE's own servers send", :aggregate_failures do
      respond_in_turn(:get, "/characters/1/location", too_many)

      expect { client.characters(1).location.get }.to raise_error(Esirb::TooManyRequests)
      expect(attempts.size).to eq 1
    end

    it "gives up after the client's retries", :aggregate_failures do
      respond_in_turn(:get, "/characters/1/location", *Array.new(3) { too_many(retry_after: "1") })

      expect { client.characters(1).location.get }.to raise_error(Esirb::TooManyRequests)
      expect(attempts.size).to eq 3
    end

    it "doesn't retry POST", :aggregate_failures do
      respond_in_turn(:post, "/characters/1/contacts", too_many(retry_after: "1"))

      expect { client.characters(1).contacts.post(body: [2]) }.to raise_error(Esirb::TooManyRequests)
      expect(attempts.size).to eq 1
    end

    it "sends the original body again on the retry" do
      respond_in_turn(:put, "/characters/1/settings", too_many(retry_after: "1"))
      client.characters(1).settings.put(body: { a: 1 })

      expect(attempts.map(&:request_body)).to eq ['{"a":1}', '{"a":1}']
    end
  end

  context "with retries: 0" do
    let(:client) { Esirb::Client.new(retries: 0) }

    it "sends each request once", :aggregate_failures do
      respond_in_turn(:get, "/status", 503)

      expect { client.status.get }.to raise_error(Esirb::ServiceUnavailable)
      expect(attempts.size).to eq 1
    end
  end

  context "with retries set in Esirb.configure" do
    before { Esirb.configure { |config| config.retries = 1 } }

    it "uses that many", :aggregate_failures do
      respond_in_turn(:get, "/status", 503, 503)

      expect { client.status.get }.to raise_error(Esirb::ServiceUnavailable)
      expect(attempts.size).to eq 2
    end
  end
end
