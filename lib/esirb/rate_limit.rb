# frozen_string_literal: true

require "faraday"

module Esirb
  # ESI's limits as reported on one response. A route uses either the per-group rate limit
  # (X-Ratelimit-*) or the older error limit (X-ESI-Error-Limit-*), never both, so the other
  # set of values is nil. See https://developers.eveonline.com/docs/services/esi/rate-limiting/
  #
  #   Esirb::RateLimit.new(response).remaining # => 1195
  class RateLimit
    WINDOW_UNITS = { "s" => 1, "m" => 60, "h" => 60 * 60 }.freeze
    COUNT_HEADERS = %w[X-Ratelimit-Remaining X-Ratelimit-Used X-ESI-Error-Limit-Remain X-ESI-Error-Limit-Reset].freeze

    # group, limit (tokens per window), window (seconds), remaining and used (what this request
    # cost) come from the rate limit; error_limit_remaining and error_limit_reset (seconds until
    # the window resets) from the error limit.
    attr_reader :group, :limit, :window, :remaining, :used, :error_limit_remaining, :error_limit_reset

    # Takes a response (or anything with headers) or the headers themselves.
    def initialize(source)
      headers = Faraday::Utils::Headers.new.update(source.respond_to?(:headers) ? source.headers : source.to_h)

      @group = headers["X-Ratelimit-Group"]
      @limit, @window = parse_limit(headers["X-Ratelimit-Limit"])
      @remaining, @used, @error_limit_remaining, @error_limit_reset =
        COUNT_HEADERS.map { |name| integer(headers[name]) }
    end

    private

    # "150/15m" => [150, 900]
    def parse_limit(value)
      match = value.to_s.match(%r{\A(\d+)/(\d+)([smh])\z})
      return [nil, nil] unless match

      [match[1].to_i, match[2].to_i * WINDOW_UNITS.fetch(match[3])]
    end

    def integer(value)
      Integer(value, exception: false) if value
    end
  end
end
