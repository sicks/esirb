# frozen_string_literal: true

require "faraday"
require_relative "errors"
require_relative "rate_limit"

module Esirb
  # Stops sending requests while ESI's error limit is nearly used up. Once that limit runs out,
  # every ESI route returns 420 until the error limit window resets, and repeatedly ignoring it can get an app
  # banned (https://developers.eveonline.com/docs/services/esi/rate-limiting/).
  #
  # The limit is counted per source IP, not per token, so its state is kept once per ESI host in
  # the cache store, where every client in every process sees it. Apps on several servers that
  # share one store will pause together, which errs on the side of sending less.
  class ErrorLimitGuard < Faraday::Middleware
    # How long to pause after a 420 that doesn't say when the error limit window resets. The window is a minute.
    DEFAULT_RESET = 60

    def initialize(app, store:, key:)
      super(app)
      @store = store
      @key = key
    end

    def call(env)
      raise_if_paused
      response = @app.call(env)
      record_error_limit(response.status, response.headers) unless cached?(response.env)
      response
    rescue ResponseError => e
      record_error_limit(e.status, e.headers)
      raise
    end

    private

    def raise_if_paused
      state = @store.read(@key)
      return unless state

      seconds = (state["reset_at"] - Time.now.to_f).ceil
      return unless seconds.positive? && state["remaining"] < RateLimit::ERROR_LIMIT_FLOOR

      raise ErrorLimitReached.new(remaining: state["remaining"], retry_after: seconds)
    end

    # Routes on the newer rate limit don't send error limit headers, and leave the state alone.
    def record_error_limit(status, headers)
      limit = RateLimit.new(headers)
      remaining = status == 420 ? 0 : limit.error_limit_remaining
      reset = limit.error_limit_reset || (DEFAULT_RESET if status == 420)
      return if remaining.nil? || reset.nil?

      @store.write(@key, { "remaining" => remaining, "reset_at" => Time.now.to_f + reset })
    end

    # A response served from the cache carries the error limit from when it was first fetched.
    def cached?(env)
      Array(env[:http_cache_trace]).include?(:fresh)
    end
  end
end
