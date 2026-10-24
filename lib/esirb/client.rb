# frozen_string_literal: true

require "faraday"
require "faraday-http-cache"
require "faraday/retry"
require_relative "version"
require_relative "configuration"
require_relative "compatibility_date"
require_relative "raise_error"
require_relative "vary_by_authorization"

module Esirb
  # Holds the ESI connection settings and starts building request paths.
  class Client
    # Sent after the app's own user_agent, so ESI can tell which library made the request.
    USER_AGENT = "esirb/#{VERSION} (+https://github.com/sicks/esirb)".freeze

    # Errors worth retrying: ESI usually recovers from these within a second or two.
    RETRY_ERRORS = [BadGateway, ServiceUnavailable, GatewayTimeout, TimeoutError, ConnectionFailed].freeze
    # Waits about 0.5s, then 1s, plus up to 50% randomness so clients don't retry in step. A
    # Retry-After header from ESI is honored, unless it asks for longer than max_interval, in
    # which case the error is raised straight away.
    RETRY_OPTIONS = { interval: 0.5, backoff_factor: 2, interval_randomness: 0.5, max_interval: 10 }.freeze

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
      Faraday.new(base_url, request: { timeout:, open_timeout: }.compact) do |c|
        use_middleware(c)
        # Last, so app middleware sits closest to the network and sees real requests, not cache hits.
        [@faraday, block].compact.each { |hook| hook.call(c) }
      end
    end

    def use_middleware(builder)
      # Before the cache, so the token is part of each cache key.
      builder.request :authorization, "Bearer", access_token if token
      builder.headers.update(default_headers)

      # Outside RaiseError, so it sees esirb's error classes and can retry by class.
      builder.request :retry, max: retries, exceptions: RETRY_ERRORS, **RETRY_OPTIONS if retries.positive?
      builder.use RaiseError
      builder.response :json, content_type: "application/json"
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
