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

    it "includes http cache middleware" do
      expect(client.connection.builder.handlers).to include Faraday::HttpCache
    end

    it "includes error response middleware" do
      expect(client.connection.builder.handlers).to include Faraday::Response::RaiseError
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

    context "with cache false" do
      let(:client) { described_class.new(cache: false) }

      it "does not include http cache middleware" do
        expect(client.connection.builder.handlers).not_to include Faraday::HttpCache
      end
    end
  end

  describe "missing methods" do
    specify "are called on a new Path" do
      expect(client.frank).to be_a Esirb::Path
    end
  end
end
