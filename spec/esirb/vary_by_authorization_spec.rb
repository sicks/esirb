# frozen_string_literal: true

RSpec.describe Esirb::VaryByAuthorization do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:connection) do
    Faraday.new do |f|
      f.use described_class
      f.adapter :test, stubs
    end
  end

  def vary_after(vary, headers: { "Authorization" => "Bearer abc" })
    response_headers = vary ? { "Vary" => vary } : {}
    stubs.get("/x") { [200, response_headers, ""] }
    connection.get("/x", nil, headers).headers["Vary"]
  end

  it "adds Authorization to Vary when the request has a token" do
    expect(vary_after("X-Tenant, Accept-Language")).to eq "X-Tenant, Accept-Language, Authorization"
  end

  it "sets Vary when the response has none" do
    expect(vary_after(nil)).to eq "Authorization"
  end

  it "leaves Vary alone without a token" do
    expect(vary_after("X-Tenant", headers: {})).to eq "X-Tenant"
  end

  it "doesn't add Authorization twice, whatever its case" do
    expect(vary_after("X-Tenant, authorization")).to eq "X-Tenant, authorization"
  end

  it "leaves Vary: * alone" do
    expect(vary_after("*")).to eq "*"
  end
end
