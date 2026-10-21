# frozen_string_literal: true

require "json"

# Helpers for request-level specs. Requests go to Faraday's test adapter instead of the network,
# so specs can check exactly what esirb sends and how it handles what comes back.
module EsiStubs
  # Swaps the client's adapter for Faraday's test adapter and returns the stubs.
  # Must be called before the client makes its first request.
  def stub_esi(client)
    Faraday::Adapter::Test::Stubs.new.tap { |stubs| client.connection.adapter(:test, stubs) }
  end

  # Stubs one endpoint and returns an array that collects the env of each request made to it.
  def stub_endpoint(stubs, verb, path, response: json_response)
    [].tap do |requests|
      stubs.public_send(verb, path) do |env|
        requests << env
        response
      end
    end
  end

  def json_response(body = {}, status: 200, headers: {})
    [status, { "Content-Type" => "application/json; charset=utf-8" }.merge(headers), JSON.generate(body)]
  end
end
