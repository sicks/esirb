# frozen_string_literal: true

require_relative "errors"

module Esirb
  # Helpers for ESI's three pagination styles, included in Path. Each route uses one of them; its
  # entry in ESI's API Explorer shows which by its parameters (page, before/after, or from_id).
  # Pages are fetched one at a time, and each goes through the cache and retries like any request.
  # See https://developers.eveonline.com/docs/services/esi/pagination/x-pages/
  module Pagination
    # Every record from a route paginated with `page` and the X-Pages header, e.g. market orders.
    #
    # All pages of one resource should share a Last-Modified. If it changes partway through, ESI
    # refreshed the data between pages, so this starts over once, and raises PagesChanged if it happens again.
    def get_all_pages(params: {}, headers: nil)
      2.times do
        records = pages_unless_changed(params, headers)
        return records if records
      end
      raise PagesChanged, "#{self} changed while its pages were being fetched, twice in a row"
    end

    # Records from a route paginated with `before` and `after` cursors, e.g. freelance jobs,
    # oldest first, as [records, after]. Save `after` and pass it back later to get only the records
    # created or changed since. Without it, this fetches everything.
    #
    # Records can repeat across pages; each appears once, matched by its "id": the newest copy when
    # following `after` toward newer records, and the one already fetched when following `before`
    # toward older records.
    def get_by_cursor(after: nil, params: {}, headers: nil)
      after ? cursor_changes(after, params, headers) : cursor_everything(params, headers)
    end

    # Records from a route paginated with `from_id`, i.e. wallet transactions, newest first. Pass
    # `stop_at:` with the newest ID you already have to fetch only the records after it.
    def get_from_id(id_key: "transaction_id", stop_at: nil, params: {}, headers: nil)
      records = []
      from_id = nil
      loop do
        page = from_id_page(from_id, id_key, params, headers)
        stop_index = stop_at && page.index { |record| record[id_key] == stop_at }
        return records + page.first(stop_index) if stop_index
        return records if page.empty?

        records.concat(page)
        from_id = page.last[id_key]
      end
    end

    private

    def pages_unless_changed(params, headers)
      first_page = get(params: params.merge(page: 1), headers:)
      records = first_page.body.dup
      (2..first_page.headers["X-Pages"].to_i).each do |page|
        response = get(params: params.merge(page:), headers:)
        return nil unless response.headers["Last-Modified"] == first_page.headers["Last-Modified"]

        records.concat(response.body)
      end
      records
    end

    # Each page after the first starts with the from_id record itself, which is dropped.
    def from_id_page(from_id, id_key, params, headers)
      return get(params:, headers:).body unless from_id

      get(params: params.merge(from_id:), headers:).body.reject { |record| record[id_key] == from_id }
    end

    # Follows `before` until a page comes back empty, prepending older records.
    def cursor_everything(params, headers)
      records, cursor = cursor_page(params, headers)
      after = cursor["after"]
      while cursor["before"]
        older, cursor = cursor_page(params.merge(before: cursor["before"]), headers)
        break if older.empty?

        ids = records.to_set { |record| record["id"] }
        records = older.reject { |record| ids.include?(record["id"]) } + records
      end
      [records, after]
    end

    # Follows `after` until a page comes back empty, replacing records that changed.
    def cursor_changes(after, params, headers)
      records = []
      loop do
        newer, cursor = cursor_page(params.merge(after:), headers)
        return [records, after] if newer.empty? || cursor["after"].nil?

        ids = newer.to_set { |record| record["id"] }
        records = records.reject { |record| ids.include?(record["id"]) } + newer
        after = cursor["after"]
      end
    end

    # A cursor page is {"cursor" => {...}, "<records>" => [...]}, where the records' key varies by route.
    def cursor_page(params, headers)
      body = get(params:, headers:).body
      records = body.find { |key, value| key != "cursor" && value.is_a?(Array) }&.last || []
      [records, body["cursor"] || {}]
    end
  end
end
