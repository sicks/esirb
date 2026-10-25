# frozen_string_literal: true

RSpec.describe Esirb::Path do
  let(:client) { Esirb::Client.new }
  let(:path) { described_class.new(client:) }

  describe "building paths from method calls" do
    it "adds the method name as a segment" do
      expect(path.alliances.to_s).to eq "/alliances"
    end

    it "adds arguments as path params" do
      expect(path.characters(123_456_789).to_s).to eq "/characters/123456789"
    end

    it "chains segments" do
      expect(path.characters(123_456_789).locations.to_s).to eq "/characters/123456789/locations"
    end

    it "adds several path params in order" do
      expect(path.route(123_456_789, 987_654_321).to_s).to eq "/route/123456789/987654321"
    end

    it "accepts string and symbol params" do
      expect(path.killmails(1, "abc").ui(:x).to_s).to eq "/killmails/1/abc/ui/x"
    end

    it "keeps `trace` as a segment now that it isn't an HTTP verb" do
      expect(path.trace.to_s).to eq "/trace"
    end
  end

  describe "reusing a path" do
    let(:character) { path.characters(1) }

    it "returns a new path from each call" do
      expect(character.location).not_to equal character
    end

    it "leaves the original path unchanged" do
      character.location

      expect(character.to_s).to eq "/characters/1"
    end

    it "builds independent paths from a shared prefix" do
      expect([character.location.to_s, character.skills.to_s])
        .to eq ["/characters/1/location", "/characters/1/skills"]
    end

    it "is frozen", :aggregate_failures do
      expect(character).to be_frozen
      expect(character.to_s).to be_frozen
    end
  end

  describe "path params" do
    it "URL-encodes reserved characters" do
      expect(path.characters("1/../../x?y=1 z").to_s).to eq "/characters/1%2F..%2F..%2Fx%3Fy%3D1%20z"
    end

    [nil, "", ".", "..", 1.5, [1], { a: 1 }].each do |value|
      it "rejects #{value.inspect}" do
        expect { path.characters(value) }.to raise_error(ArgumentError)
      end
    end

    it "rejects keyword arguments" do
      expect { path.markets(10_000_002, type_id: 34) }.to raise_error(ArgumentError, /params:/)
    end
  end

  describe "hyphenated ESI segments" do
    it "are reached with the underscored method name" do
      expect(path.characters(1).freelance_jobs(5).participation.to_s)
        .to eq "/characters/1/freelance-jobs/5/participation"
    end

    it "cover every listed segment" do
      described_class::HYPHENATED_SEGMENTS.each do |method_name, segment|
        expect(path.public_send(method_name).to_s).to eq "/#{segment}"
      end
    end

    it "leave underscored ESI segments alone" do
      expect(path.universe.system_kills.to_s).to eq "/universe/system_kills"
    end
  end

  describe "#segment" do
    it "adds segments exactly as given" do
      expect(path.characters(1).segment("new-thing", 5).segment("freelance_jobs").to_s)
        .to eq "/characters/1/new-thing/5/freelance_jobs"
    end

    it "encodes and validates like method calls", :aggregate_failures do
      expect(path.segment("a b").to_s).to eq "/a%20b"
      expect { path.segment(nil) }.to raise_error(ArgumentError)
    end
  end

  describe "method names that aren't segments" do
    it "leaves conversion hooks to Ruby", :aggregate_failures do
      alliances = path.alliances

      expect([alliances].flatten).to eq [alliances]
      expect { path.to_str }.to raise_error(NoMethodError)
    end

    it "rejects names that can't be ESI segments", :aggregate_failures do
      expect { path.alliances? }.to raise_error(NoMethodError)
      expect { path.Alliances }.to raise_error(NoMethodError)
    end

    it "reports segment names in respond_to?", :aggregate_failures do
      expect(path).to respond_to(:alliances)
      expect(path).not_to respond_to(:to_ary)
      expect(path).not_to respond_to(:alliances?)
    end
  end

  describe ".new" do
    it "requires a client" do
      expect { described_class.new(client: nil) }.to raise_error(ArgumentError, /client/)
    end
  end

  describe "HTTP verbs" do
    let(:connection) { instance_double(Faraday::Connection) }
    let(:client) { instance_double(Esirb::Client, connection:) }

    described_class::VERBS.each do |verb|
      it "forwards #{verb} to the client's connection" do
        allow(connection).to receive(verb)
        path.alliances.public_send(verb)

        expect(connection).to have_received(verb).with("/alliances")
      end
    end

    it "no longer offers trace" do
      expect(described_class::VERBS).not_to include :trace
    end

    it "rejects unknown options" do
      expect { path.alliances.get(param: { page: 1 }) }.to raise_error(ArgumentError)
    end
  end
end
