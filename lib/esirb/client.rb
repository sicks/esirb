# frozen_string_literal: true

require "faraday"
require "faraday-http-cache"
require_relative "version"
require_relative "configuration"
require_relative "compatibility_date"
require_relative "raise_error"
require_relative "retry"
require_relative "error_limit_guard"
require_relative "vary_by_authorization"

module Esirb
  # Holds the ESI connection settings and starts building request paths.
  class Client
    # Sent after the app's own user_agent, so ESI can tell which library made the request.
    USER_AGENT = "esirb/#{VERSION} (+https://github.com/sicks/esirb)".freeze

    attr_reader :token, :base_url, :compatibility_date, :tenant, :language, :cache_store, :user_agent,
                :timeout, :open_timeout, :retries, :connection

    # token: an ESI access token, or something that responds to call and returns one. A callable
    # is asked before every request, so an app can refresh its token without building a new client.
    #
    # Options not given here come from Esirb.configuration: base_url, compatibility_date, tenant,
    # language, user_agent, cache_store, timeout, open_timeout, retries and faraday. A nil tenant or
    # language leaves that header out, and a nil cache_store turns caching off. compatibility_date
    # must be a YYYY-MM-DD string or a Date: without one, ESI would use its oldest behavior.
    #
    # A block is called with the Faraday connection builder after the configured faraday hook, so
    # it can add middleware or change the adapter for this client only.
    def initialize(token: nil, **options, &block)
      check_arguments(token, options)

      @token = token
      apply_settings(Esirb.configuration.to_h.merge(options))
      # Built here rather than on first use, so threads sharing a client never race to build it.
      @connection = build_connection(block)
    end

    # Starts a path with a segment exactly as given, for segments that can't be reached by method name.
    def segment(name, *params)
      Path.new(client: self).segment(name, *params)
    end

    def method_missing(name, *, **)
      return super unless Path.segment_name?(name)

      Path.new(client: self).public_send(name, *, **)
    end

    def respond_to_missing?(name, include_private = false)
      Path.segment_name?(name) || super
    end

    private

    def build_connection(block)
      # ESI reads array params as repeated keys (categories=a&categories=b), not Faraday's default
      # categories[]=a&categories[]=b. Checked live against /characters/{id}/search (MP-230).
      request = { timeout:, open_timeout:, params_encoder: Faraday::FlatParamsEncoder }.compact
      Faraday.new(base_url, request:) do |c|
        use_middleware(c)
        # Last, so app middleware sits closest to the network and sees real requests, not cache hits.
        [@faraday, block].compact.each { |hook| hook.call(c) }
      end
    end

    def use_middleware(builder)
      # Before the cache, so the token is part of each cache key.
      builder.request :authorization, "Bearer", access_token if token
      builder.headers.update(default_headers)

      use_error_handling(builder)
      builder.response :json
      # Inside the JSON parser, so the cache stores raw response bodies.
      use_cache(builder) if cache_store

      builder.request :json
    end

    # What the authorization middleware sends: the string itself, or a lambda it calls before each
    # request. The lambda refuses a blank token rather than sending "Bearer " to ESI.
    def access_token
      return token unless token.respond_to?(:call)

      lambda do
        value = token.call
        raise Error, "token callable returned #{value.inspect} instead of an access token" if value.to_s.strip.empty?

        value
      end
    end

    def check_arguments(token, options)
      unknown = options.keys - Configuration::DEFAULTS.keys
      raise ArgumentError, "unknown option#{"s" if unknown.size > 1}: #{unknown.join(", ")}" if unknown.any?

      check_callable(:faraday, options[:faraday])
      check_retries(options.fetch(:retries, 0))
      check_callable(:token, token, strings: true)
    end

    # A request without a date gets ESI's oldest behavior, so a missing date is an error, not a default.
    def check_retries(retries)
      return if retries.is_a?(Integer) && retries >= 0

      raise ArgumentError, "retries must be an Integer of 0 or more, got #{retries.inspect}"
    end

    def check_callable(name, value, strings: false)
      return if value.nil? || value.respond_to?(:call) || (strings && value.is_a?(String))

      expected = strings ? "a string or something that responds to call" : "something that responds to call"
      raise ArgumentError, "#{name} must be #{expected}, got #{value.class}"
    end

    # Keys cache entries on the URL plus the headers in Vary: tenant, language, compatibility date
    # and, through VaryByAuthorization, the token. Because every entry is per token, the store
    # acts as a private cache and keeps ESI's `Cache-Control: private` responses too.
    def use_cache(builder)
      builder.use :http_cache, store: cache_store, strategy: Faraday::HttpCache::Strategies::ByVary,
                               shared_cache: false
      builder.use VaryByAuthorization
    end

    def apply_settings(settings)
      (Configuration::DEFAULTS.keys - %i[user_agent compatibility_date]).each do |name|
        instance_variable_set(:"@#{name}", settings[name])
      end
      @compatibility_date = CompatibilityDate.parse(settings[:compatibility_date])
      app_user_agent = settings[:user_agent].to_s.strip
      @user_agent = app_user_agent.empty? ? USER_AGENT : "#{app_user_agent} #{USER_AGENT}"
    end

    # Retry sits outside RaiseError, so it sees esirb's errors. ErrorLimitGuard sits inside Retry,
    # so it checks and records every attempt; it needs the shared cache store.
    def use_error_handling(builder)
      builder.use Retry, retries: retries if retries.positive?
      builder.use ErrorLimitGuard, store: cache_store, key: error_limit_key if cache_store
      builder.use RaiseError
    end

    # One per ESI host and tenant: ESI counts the error limit per source IP, not per token.
    def error_limit_key
      "esirb:error-limit:#{base_url}:#{tenant}"
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
