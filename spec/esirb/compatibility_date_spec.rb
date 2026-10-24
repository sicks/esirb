# frozen_string_literal: true

RSpec.describe Esirb::CompatibilityDate do
  describe ".parse" do
    it "returns a YYYY-MM-DD string as given" do
      expect(described_class.parse("2026-06-09")).to eq "2026-06-09"
    end

    it "accepts a date between ESI's published compatibility dates" do
      expect(described_class.parse("2026-07-01")).to eq "2026-07-01"
    end

    it "turns a Date into a YYYY-MM-DD string" do
      expect(described_class.parse(Date.new(2026, 6, 9))).to eq "2026-06-09"
    end

    it "rejects nil, which would get ESI's oldest behavior" do
      expect { described_class.parse(nil) }.to raise_error(ArgumentError, /can't be nil.*oldest behavior/)
    end

    # ESI itself rejects "2026-8-18" with "Expected YYYY-MM-DD".
    ["2026-8-18", "2026-02-30", "yesterday", 20_260_818].each do |value|
      it "rejects #{value.inspect}" do
        expect { described_class.parse(value) }.to raise_error(ArgumentError, /YYYY-MM-DD date, got #{value.inspect}/)
      end
    end

    context "when it's 10:00 UTC on 2026-10-24, before ESI's 11:00 UTC rollover" do
      before { allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 24, 10)) }

      it "accepts ESI's current date, 2026-10-23" do
        expect(described_class.parse("2026-10-23")).to eq "2026-10-23"
      end

      it "rejects 2026-10-24, which is still in the future for ESI" do
        expect { described_class.parse("2026-10-24") }
          .to raise_error(ArgumentError, /2026-10-24 is in the future; ESI's current date is 2026-10-23/)
      end

      it "accepts a DateTime later in ESI's current day, ignoring its time" do
        expect(described_class.parse(DateTime.new(2026, 10, 23, 23, 59))).to eq "2026-10-23"
      end

      it "rejects a future Date too" do
        expect { described_class.parse(Date.new(2026, 10, 24)) }.to raise_error(ArgumentError, /in the future/)
      end
    end
  end

  describe ".today" do
    it "is the UTC date until 11:00 UTC rolls it over" do
      allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 24, 10, 59), Time.utc(2026, 10, 24, 11))

      expect([described_class.today, described_class.today]).to eq [Date.new(2026, 10, 23), Date.new(2026, 10, 24)]
    end
  end
end
