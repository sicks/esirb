# frozen_string_literal: true

require "faraday"
require_relative "errors"

module Esirb
  # Retries requests that failed for reasons that usually clear up on their own, up to `retries`
  # times in all, whatever the reason. Sits outside RaiseError, so it sees esirb's errors.
  class Retry < Faraday::Middleware
    # Usually transient: ESI tends to recover within a second or two.
    TRANSIENT = [BadGateway, ServiceUnavailable, GatewayTimeout, TimeoutError, ConnectionFailed].freeze
    # Safe to repeat. POST isn't, since it might do something twice, like sending a mail.
    METHODS = %i[delete get head options put].freeze
    # Longest Retry-After worth waiting for, in seconds. Anything longer is raised for the app to handle.
    MAX_WAIT = 10

    def self.pause(seconds)
      sleep(seconds)
    end

    def initialize(app, retries:)
      super(app)
      @retries = retries
    end

    # body is the original request body: after a failure, env.body holds the response's.
    def call(env, body: env.body, attempt: 0)
      env.body = body
      @app.call(env)
    rescue Error => e
      wait = wait_for(env, e, attempt)
      raise unless wait

      self.class.pause(wait)
      call(env, body:, attempt: attempt + 1)
    end

    private

    # Seconds to wait before retrying, or nil to raise the error.
    def wait_for(env, error, attempt)
      return unless retry_allowed?(env, error, attempt)
      return retry_after(error) if error.is_a?(TooManyRequests)
      return unless TRANSIENT.any? { |error_class| error.is_a?(error_class) }

      retry_after?(error) ? retry_after(error) : backoff(attempt)
    end

    def retry_allowed?(env, error, attempt)
      attempt < @retries && METHODS.include?(env.method) && !error_limit_low?(error)
    end

    # Each failed retry is another error, so stop when the error limit is nearly used up.
    def error_limit_low?(error)
      error.is_a?(ResponseError) && error.rate_limit.error_limit_low?
    end

    # About 0.5s, then 1s, then 2s..., plus up to 50% so many clients don't retry in step.
    def backoff(attempt)
      0.5 * (2**attempt) * (1 + (rand * 0.5))
    end

    def retry_after?(error)
      error.is_a?(ResponseError) && !error.headers["Retry-After"].nil?
    end

    # ESI's Retry-After, or nil if it's missing or too long to wait for.
    def retry_after(error)
      seconds = Float(error.headers["Retry-After"], exception: false) if retry_after?(error)
      seconds if seconds && seconds <= MAX_WAIT
    end
  end
end
