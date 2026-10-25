# frozen_string_literal: true

require_relative "rate_limit"

module Esirb
  # Base class for everything esirb raises.
  class Error < StandardError; end

  # Raised when the connection to ESI fails, including TLS errors.
  class ConnectionFailed < Error; end

  # Raised when ESI doesn't answer in time.
  class TimeoutError < Error; end

  # Raised for an error status from ESI. ESI's error bodies look like {"error" => "System not found"}.
  class ResponseError < Error
    attr_reader :status, :headers, :body, :response

    def self.for_status(status)
      STATUS_ERRORS.fetch(status) { status >= 500 ? ServerError : ClientError }
    end

    def initialize(env)
      @status = env.status
      @headers = env.response_headers
      @body = env.body
      @response = env.response
      super("#{status} #{detail(env)} (#{env.method.to_s.upcase} #{env.url})")
    end

    # ESI's rate or error limit as of this response.
    def rate_limit
      RateLimit.new(headers)
    end

    private

    def detail(env)
      message = body["error"] if body.is_a?(Hash)
      return message if message.is_a?(String) && !message.empty?

      env.reason_phrase.to_s.empty? ? "error" : env.reason_phrase
    end
  end

  # Raised without sending the request, because ESI's error limit is nearly used up and its window
  # hasn't reset yet. Only happens with a cache_store; see ErrorLimitGuard.
  class ErrorLimitReached < Error
    # Seconds until ESI's error limit window resets.
    attr_reader :retry_after

    def initialize(remaining:, retry_after:)
      @retry_after = retry_after
      super("ESI's error limit is nearly used up (#{remaining} errors left), " \
            "so requests are paused for #{retry_after} more seconds")
    end
  end

  # Any 4xx status without its own class.
  class ClientError < ResponseError; end

  class BadRequest < ClientError; end
  class Unauthorized < ClientError; end
  class Forbidden < ClientError; end
  class NotFound < ClientError; end

  # ESI's error limit (420) or rate limit (429).
  class RateLimited < ClientError
    # Seconds to wait before trying again, or nil if ESI didn't say.
    def retry_after
      value = status == 429 ? headers["Retry-After"] : headers["X-ESI-Error-Limit-Reset"]
      Integer(value, exception: false) if value
    end
  end

  # 420: too many errors in the error limit's window. The limit is global, so every ESI route
  # returns 420 until it resets. Never retried.
  class ErrorLimited < RateLimited; end

  # 429: a rate limit group's tokens are used up. Retried when Retry-After is short.
  class TooManyRequests < RateLimited; end

  # Any 5xx status.
  class ServerError < ResponseError; end

  # Usually transient on ESI's side, so esirb retries these (see the retries option).
  class BadGateway < ServerError; end
  class ServiceUnavailable < ServerError; end
  class GatewayTimeout < ServerError; end

  ResponseError::STATUS_ERRORS = {
    400 => BadRequest,
    401 => Unauthorized,
    403 => Forbidden,
    404 => NotFound,
    420 => ErrorLimited,
    429 => TooManyRequests,
    502 => BadGateway,
    503 => ServiceUnavailable,
    504 => GatewayTimeout
  }.freeze
end
