# frozen_string_literal: true

RSpec.describe Esirb::RaiseError do
  let(:client) { Esirb::Client.new }
  let(:stubs) { stub_esi(client) }

  def error_for(status, body: { error: "Something went wrong" }, headers: {})
    stub_endpoint(stubs, :get, "/universe/systems/1", response: json_response(body, status:, headers:))
    client.universe.systems(1).get
  rescue Esirb::Error => e
    e
  end

  describe "status classes" do
    {
      400 => Esirb::BadRequest,
      401 => Esirb::Unauthorized,
      403 => Esirb::Forbidden,
      404 => Esirb::NotFound,
      420 => Esirb::RateLimited,
      429 => Esirb::RateLimited,
      418 => Esirb::ClientError,
      500 => Esirb::ServerError,
      501 => Esirb::ServerError,
      502 => Esirb::BadGateway,
      503 => Esirb::ServiceUnavailable,
      504 => Esirb::GatewayTimeout
    }.each do |status, error_class|
      it "raises #{error_class} for #{status}" do
        expect(error_for(status)).to be_an_instance_of(error_class)
      end
    end

    it "makes every status error an Esirb::ResponseError and an Esirb::Error" do
      expect(Esirb::ResponseError::STATUS_ERRORS.values + [Esirb::ClientError, Esirb::ServerError])
        .to all(be <= Esirb::ResponseError).and all(be <= Esirb::Error)
    end

    it "groups 502, 503 and 504 under ServerError" do
      expect([Esirb::BadGateway, Esirb::ServiceUnavailable, Esirb::GatewayTimeout]).to all(be < Esirb::ServerError)
    end

    it "groups 4xx classes under ClientError" do
      expect([Esirb::BadRequest, Esirb::Unauthorized, Esirb::Forbidden, Esirb::NotFound, Esirb::RateLimited])
        .to all(be < Esirb::ClientError)
    end
  end

  describe "details" do
    subject(:error) do
      error_for(404, body: { error: "System not found" }, headers: { "X-ESI-Error-Limit-Remain" => "99" })
    end

    it "uses ESI's error message, the status and the request" do
      expect(error.message).to eq "404 System not found (GET https://esi.evetech.net/universe/systems/1)"
    end

    it "exposes the status, parsed body, headers and response", :aggregate_failures do
      expect(error.status).to eq 404
      expect(error.body).to eq("error" => "System not found")
      expect(error.headers["x-esi-error-limit-remain"]).to eq "99"
      expect(error.response).to be_a Faraday::Response
    end

    it "still has a message when the body has no error and there's no reason phrase" do
      stub_endpoint(stubs, :get, "/universe/systems/1", response: [502, { "Content-Type" => "text/html" }, "<html>"])

      expect { client.universe.systems(1).get }.to raise_error(Esirb::ServerError, /\A502 error \(GET /)
    end
  end

  describe "RateLimited#retry_after" do
    it "reads X-ESI-Error-Limit-Reset for ESI's error limit (420)" do
      expect(error_for(420, headers: { "X-ESI-Error-Limit-Reset" => "37" }).retry_after).to eq 37
    end

    it "reads Retry-After for the rate limit (429)" do
      expect(error_for(429, headers: { "Retry-After" => "12" }).retry_after).to eq 12
    end

    it "is nil when ESI doesn't say" do
      expect(error_for(429).retry_after).to be_nil
    end
  end

  describe "connection problems" do
    {
      Faraday::ConnectionFailed => Esirb::ConnectionFailed,
      Faraday::SSLError => Esirb::ConnectionFailed,
      Faraday::TimeoutError => Esirb::TimeoutError,
      Faraday::ParsingError => Esirb::Error
    }.each do |faraday_error, esirb_error|
      it "raises #{esirb_error} for #{faraday_error}, keeping it as the cause", :aggregate_failures do
        stubs.get("/universe/systems/1") { raise faraday_error, "boom" }

        expect { client.universe.systems(1).get }.to raise_error(esirb_error, "boom") do |error|
          expect(error.cause).to be_a faraday_error
        end
      end
    end
  end
end
