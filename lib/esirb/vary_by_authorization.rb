# frozen_string_literal: true

require "faraday"

module Esirb
  # Adds Authorization to a response's Vary header when the request carried a token, so the
  # ByVary cache strategy keys authenticated responses by token. ESI's Vary doesn't name it,
  # which would let a cache store shared between clients serve one character's data to another.
  class VaryByAuthorization < Faraday::Middleware
    def on_complete(env)
      return unless env.request_headers["Authorization"]

      names = env.response_headers["Vary"].to_s.split(/[\s,]+/).reject(&:empty?)
      return if names.include?("*") || names.any? { |name| name.casecmp?("Authorization") }

      env.response_headers["Vary"] = [*names, "Authorization"].join(", ")
    end
  end
end
