# frozen_string_literal: true

RSpec.describe Esirb::Pagination do
  let(:client) { Esirb::Client.new }
  let(:stubs) { stub_esi(client) }
  let(:requests) { [] }

  # Stubs GET `path` so each request is answered by the block, given the request's params.
  def answer(path, &block)
    stubs.get(path) do |env|
      requests << env
      block.call(env.params)
    end
  end

  def ids(records, key = "id")
    records.map { |record| record[key] }
  end

  describe "#get_all_pages" do
    def page(records, pages: 3, last_modified: "Sat, 25 Oct 2026 02:00:00 GMT")
      json_response(records, headers: { "X-Pages" => pages.to_s, "Last-Modified" => last_modified })
    end

    it "fetches every page in order and combines them", :aggregate_failures do
      answer("/markets/10000002/orders") { |params| page([{ "order_id" => params["page"].to_i }]) }
      orders = client.markets(10_000_002).orders.get_all_pages

      expect(ids(orders, "order_id")).to eq [1, 2, 3]
      expect(requests.map { |request| request.params["page"] }).to eq %w[1 2 3]
    end

    it "makes one request when there's only one page" do
      answer("/universe/types") { json_response([34, 35]) }

      expect([client.universe.types.get_all_pages, requests.size]).to eq [[34, 35], 1]
    end

    it "keeps the caller's params and headers on every page" do
      answer("/markets/10000002/orders") { page([]) }
      client.markets(10_000_002).orders.get_all_pages(params: { type_id: 34 }, headers: { "X-Custom" => "1" })

      expect(requests.map { |request| [request.params["type_id"], request.request_headers["X-Custom"]] })
        .to all(eq %w[34 1])
    end

    it "starts over once when Last-Modified changes partway through", :aggregate_failures do
      versions = %w[old new new new]
      answer("/markets/10000002/orders") do |params|
        version = versions.shift
        page([{ "order_id" => params["page"].to_i, "version" => version }], pages: 2, last_modified: version)
      end
      orders = client.markets(10_000_002).orders.get_all_pages

      expect(orders.map { |order| order["version"] }).to eq %w[new new]
      expect(requests.size).to eq 4
    end

    it "raises PagesChanged when Last-Modified changes partway through twice" do
      versions = %w[a b c d]
      answer("/markets/10000002/orders") { page([], pages: 2, last_modified: versions.shift) }

      expect { client.markets(10_000_002).orders.get_all_pages }.to raise_error(Esirb::PagesChanged, %r{/markets/})
    end
  end

  describe "#get_by_cursor" do
    def cursor_page(records, before: nil, after: nil, key: "freelance_jobs")
      json_response({ "cursor" => { "before" => before, "after" => after }.compact, key => records })
    end

    it "fetches everything, oldest first, and returns the after token to save", :aggregate_failures do
      answer("/freelance-jobs") do |params|
        case params["before"]
        when nil then cursor_page([{ "id" => 3, "v" => "new" }, { "id" => 4 }], before: "b1", after: "a1")
        when "b1" then cursor_page([{ "id" => 1 }, { "id" => 2 }, { "id" => 3, "v" => "old" }], before: "b2")
        else cursor_page([])
        end
      end
      jobs, after = client.freelance_jobs.get_by_cursor

      expect(ids(jobs)).to eq [1, 2, 3, 4]
      expect(jobs.find { |job| job["id"] == 3 }["v"]).to eq "new"
      expect(after).to eq "a1"
    end

    it "fetches only what changed since a saved after token, keeping each record's newest copy", :aggregate_failures do
      answer("/freelance-jobs") do |params|
        case params["after"]
        when "a1" then cursor_page([{ "id" => 4, "v" => 2 }, { "id" => 5, "v" => 1 }], after: "a2")
        when "a2" then cursor_page([{ "id" => 5, "v" => 2 }], after: "a3")
        else cursor_page([], after: "a3")
        end
      end
      jobs, after = client.freelance_jobs.get_by_cursor(after: "a1")

      expect(jobs).to eq [{ "id" => 4, "v" => 2 }, { "id" => 5, "v" => 2 }]
      expect(after).to eq "a3"
    end

    it "finds the records whatever their key is called" do
      answer("/paragon-hub/skinr") { |params| cursor_page(params["before"] ? [] : [{ "id" => 9 }], key: "listings") }

      expect(ids(client.paragon_hub.skinr.get_by_cursor.first)).to eq [9]
    end

    it "keeps the caller's params on every page" do
      answer("/freelance-jobs") { |params| cursor_page(params["before"] ? [] : [{ "id" => 1 }], before: "b1") }
      client.freelance_jobs.get_by_cursor(params: { limit: 50 })

      expect(requests.map { |request| request.params["limit"] }).to eq %w[50 50]
    end
  end

  describe "#get_from_id" do
    let(:transactions) { client.characters(1).wallet.transactions }

    def records(*ids)
      json_response(ids.map { |id| { "transaction_id" => id } })
    end

    before do
      answer("/characters/1/wallet/transactions") do |params|
        case params["from_id"]
        when nil then records(30, 29, 28)
        when "28" then records(28, 27, 26)
        else records(26)
        end
      end
    end

    it "follows from_id from the newest record to the oldest, without repeats" do
      expect(ids(transactions.get_from_id, "transaction_id")).to eq [30, 29, 28, 27, 26]
    end

    it "stops at an ID the app already has", :aggregate_failures do
      expect(ids(transactions.get_from_id(stop_at: 28), "transaction_id")).to eq [30, 29]
      expect(requests.size).to eq 1
    end
  end

  it "returns nothing for an empty from_id route" do
    answer("/characters/1/wallet/transactions") { json_response([]) }

    expect(client.characters(1).wallet.transactions.get_from_id).to eq []
  end
end
