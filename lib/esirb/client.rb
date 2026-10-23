# frozen_string_literal: true

require "faraday"
require "faraday-http-cache"
require_relative "version"
require_relative "configuration"
require_relative "raise_error"
require_relative "vary_by_authorization"

module Esirb
  # Holds the ESI connection settings and starts building request paths.
  class Client
    # Sent after the app's own user_agent, so ESI can tell which library made the request.
    USER_AGENT = "esirb/#{VERSION} (+https://github.com/sicks/esirb)".freeze

    attr_reader :token, :path, :base_url, :compatibility_date, :tenant, :language, :cache_store, :user_agent

    # Options not given here come from Esirb.configuration: base_url, compatibility_date, tenant,
    # language, user_agent and cache_store. A nil tenant, language or
    # compatibility_date leaves that header out, and a nil cache_store turns caching off.
    def initialize(token: nil, **options)
      unknown = options.keys - Configuration::DEFAULTS.keys
      raise ArgumentError, "unknown option#{"s" if unknown.size > 1}: #{unknown.join(", ")}" if unknown.any?

      @token = token
      apply_settings(Esirb.configuration.to_h.merge(options))
    end

    def connection
      @connection ||= Faraday.new(base_url) do |c|
        # Before the cache, so the token is part of each cache key.
        c.request :authorization, "Bearer", token if token
        c.headers.update(default_headers)

        c.use RaiseError
        c.response :json, content_type: "application/json"
        # Inside the JSON parser, so the cache stores raw response bodies.
        use_cache(c) if cache_store

        c.request :json
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

    private

    # Keys cache entries on the URL plus the headers in Vary: tenant, language, compatibility date
    # and, through VaryByAuthorization, the token. Because every entry is per token, the store
    # acts as a private cache and keeps ESI's `Cache-Control: private` responses too.
    def use_cache(builder)
      builder.use :http_cache, store: cache_store, strategy: Faraday::HttpCache::Strategies::ByVary,
                               shared_cache: false
      builder.use VaryByAuthorization
    end

    def apply_settings(settings)
      @base_url = settings[:base_url]
      @compatibility_date = settings[:compatibility_date]
      @tenant = settings[:tenant]
      @language = settings[:language]
      @cache_store = settings[:cache_store]
      app_user_agent = settings[:user_agent].to_s.strip
      @user_agent = app_user_agent.empty? ? USER_AGENT : "#{app_user_agent} #{USER_AGENT}"
    end

    def default_headers
      {
        "Accept" => "application/json",
        "Accept-Language" => language,
        "X-Tenant" => tenant,
        "X-Compatibility-Date" => compatibility_date,
        "User-Agent" => user_agent
      }.compact
    end
  end
end
