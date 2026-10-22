# frozen_string_literal: true

require "faraday"
require "faraday-http-cache"
require_relative "version"

module Esirb
  # Holds the ESI connection settings and starts building request paths.
  class Client
    BASE_URL = "https://esi.evetech.net"
    DEFAULT_HEADERS = {
      "Accept" => "application/json",
      "Accept-Language" => "en",
      "X-Tenant" => "tranquility",
      "X-Compatibility-Date" => "2026-06-09"
    }.freeze
    # Sent after the app's own user_agent, so ESI can tell which library made the request.
    USER_AGENT = "esirb/#{VERSION} (+https://github.com/sicks/esirb)".freeze

    attr_reader :token, :path, :tenant, :language, :cache, :cache_store, :raise_errors, :user_agent

    # user_agent: your app's name, version and contact info, e.g. "mappy/1.2 (admin@example.com)".
    # CCP asks every ESI client to identify itself this way. esirb adds its own name after it.
    def initialize(token: nil, tenant: "tranquility", language: "en", cache: true, cache_store: nil,
                   raise_errors: true, user_agent: nil)
      @token = token
      @user_agent = user_agent.to_s.strip.empty? ? USER_AGENT : "#{user_agent.strip} #{USER_AGENT}"
      @tenant = tenant
      @language = language
      @cache = cache
      @cache_store = cache_store
      @raise_errors = raise_errors
    end

    def connection
      @connection ||= Faraday.new(BASE_URL) do |c|
        if cache
          c.use :http_cache, store: cache_store, strategy: Faraday::HttpCache::Strategies::ByUrl, serializer: Marshal
        end

        c.headers = DEFAULT_HEADERS
        c.headers["X-Tenant"] = tenant if tenant
        c.headers["Accept-Language"] = language if language
        c.headers["User-Agent"] = user_agent

        c.request :authorization, "Bearer", token if token
        c.request :json

        c.response :raise_error if raise_errors
        c.response :json, content_type: "application/json"
      end
    end

    # Starts a path with a segment exactly as given, for segments that can't be reached by method name.
    def segment(name, *params)
      Path.new(client: self).segment(name, *params)
    end

    def method_missing(name, *, **)
      return super unless Path.segment_name?(name)

      @path = Path.new(client: self).public_send(name, *, **)
    end

    def respond_to_missing?(name, include_private = false)
      Path.segment_name?(name) || super
    end
  end
end
