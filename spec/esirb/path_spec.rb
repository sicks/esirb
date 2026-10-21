# frozen_string_literal: true

RSpec.describe Esirb::Path do
  let(:path) { described_class.new }

  describe "missing methods passed to a Path will append to the string" do
    subject { path.string }

    context "with path.alliances" do
      before { path.alliances }

      it { is_expected.to eq "/alliances" }
    end

    context "with path.characters(123456789)" do
      before { path.characters(123_456_789) }

      it { is_expected.to eq "/characters/123456789" }
    end

    context "with path.characters(123456789).locations" do
      before { path.characters(123_456_789).locations }

      it { is_expected.to eq "/characters/123456789/locations" }
    end

    context "with path.route(123456789, 987654321)" do
      before { path.route(123_456_789, 987_654_321) }

      it { is_expected.to eq "/route/123456789/987654321" }
    end
  end

  describe "HTTP verbs are forwarded to the client's connection object" do
    let(:connection) { instance_double("Faraday::Connection") }
    let(:client) { instance_double("Esirb::Client", connection:) }
    let(:path) { described_class.new(client:).alliances }

    %i[get head delete trace post put patch].each do |verb|
      before { allow(connection).to receive(verb) }

      it "forwards #{verb} to client connection" do
        path.send(verb)
        expect(connection).to have_received(verb)
      end
    end
  end
end
