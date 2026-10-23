# frozen_string_literal: true

require "faraday"
require_relative "errors"

module Esirb
  # Raises esirb's errors in place of Faraday's: a ResponseError subclass for error statuses, and
  # ConnectionFailed, TimeoutError or Error for failures with no response. The Faraday error is
  # kept as the exception's cause.
  class RaiseError < Faraday::Middleware
    def call(env)
      super
    rescue Faraday::TimeoutError => e
      raise Esirb::TimeoutError, e.message
    rescue Faraday::ConnectionFailed, Faraday::SSLError => e
      raise Esirb::ConnectionFailed, e.message
    rescue Faraday::Error => e
      raise Esirb::Error, e.message
    end

    def on_complete(env)
      return unless env.status.to_i >= 400

      raise ResponseError.for_status(env.status), env
    end
  end
end
