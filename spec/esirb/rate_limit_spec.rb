# frozen_string_literal: true

RSpec.describe Esirb::RateLimit do
  context "with the rate limit headers" do
    subject(:rate_limit) do
      described_class.new(
        "x-ratelimit-group" => "char-location", "x-ratelimit-limit" => "1200/15m",
        "x-ratelimit-remaining" => "1195", "x-ratelimit-used" => "5"
      )
    end

    it "reads the group, limit, window, remaining and used", :aggregate_failures do
      expect([rate_limit.group, rate_limit.limit, rate_limit.window]).to eq ["char-location", 1200, 900]
      expect([rate_limit.remaining, rate_limit.used]).to eq [1195, 5]
    end

    it "leaves the error limit nil, since a route only uses one system" do
      expect([rate_limit.error_limit_remaining, rate_limit.error_limit_reset]).to eq [nil, nil]
    end
  end

  context "with the error limit headers" do
    subject(:rate_limit) { described_class.new("X-ESI-Error-Limit-Remain" => "100", "X-ESI-Error-Limit-Reset" => "46") }

    it "reads the errors left and the seconds until the window resets" do
      expect([rate_limit.error_limit_remaining, rate_limit.error_limit_reset]).to eq [100, 46]
    end

    it "leaves the rate limit nil" do
      expect([rate_limit.group, rate_limit.limit, rate_limit.window, rate_limit.remaining]).to all(be_nil)
    end
  end

  { "150/15m" => [150, 900], "3600/1h" => [3600, 3600], "10/30s" => [10, 30] }.each do |header, (limit, window)|
    it "parses a #{header} limit as #{limit} tokens per #{window} seconds" do
      expect(described_class.new("X-Ratelimit-Limit" => header).then { [_1.limit, _1.window] }).to eq [limit, window]
    end
  end

  it "ignores a limit it can't parse" do
    expect(described_class.new("X-Ratelimit-Limit" => "lots").then { [_1.limit, _1.window] }).to eq [nil, nil]
  end

  it "reads headers in any case" do
    expect(described_class.new("X-RATELIMIT-REMAINING" => "7").remaining).to eq 7
  end

  it "takes a response as well as headers" do
    response = Faraday::Response.new(status: 200, response_headers: { "X-Ratelimit-Used" => "2" })

    expect(described_class.new(response).used).to eq 2
  end
end
