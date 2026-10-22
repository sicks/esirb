# frozen_string_literal: true

require "faraday"
require "faraday-http-cache"
require_relative "version"
require_relative "configuration"

module Esirb
  # Holds the ESI connection settings and starts building request paths.
  class Client
    # Sent after the app's own user_agent, so ESI can tell which library made the request.
    USER_AGENT = "esirb/#{VERSION} (+https://github.com/sicks/esirb)".freeze

    attr_reader :token, :path, :base_url, :compatibility_date, :tenant, :language, :cache, :cache_store,
                :raise_errors, :user_agent

    # Options not given here come from Esirb.configuration: base_url, compatibility_date, tenant,
    # language, user_agent and raise_errors. A nil tenant, language or compatibility_date leaves
    # that header out.
    def initialize(token: nil, cache: true, cache_store: nil, **options)
      unknown = options.keys - Configuration::DEFAULTS.keys
      raise ArgumentError, "unknown option#{"s" if unknown.size > 1}: #{unknown.join(", ")}" if unknown.any?

      @token = token
      @cache = cache
      @cache_store = cache_store
      apply_settings(Esirb.configuration.to_h.merge(options))
    end

    def connection
      @connection ||= Faraday.new(base_url) do |c|
        if cache
          c.use :http_cache, store: cache_store, strategy: Faraday::HttpCache::Strategies::ByUrl, serializer: Marshal
        end

        c.headers.update(default_headers)

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

    private

    def apply_settings(settings)
      @base_url = settings[:base_url]
      @compatibility_date = settings[:compatibility_date]
      @tenant = settings[:tenant]
      @language = settings[:language]
      @raise_errors = settings[:raise_errors]
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
