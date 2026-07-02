# frozen_string_literal: true

require "faraday"
require "faraday-http-cache"

module Esirb
  class Client
    BASE_URL = "https://esi.evetech.net"
    DEFAULT_HEADERS = {
      "Accept" => "application/json",
      "Accept-Language" => "en",
      "If-Modified-Since" => "",
      "If-None-Match" => "",
      "X-Tenant" => "tranquility",
      "X-Compatibility-Date" => "2026-06-09"
    }

    attr_reader :token, :path, :tenant, :language, :cache, :cache_store, :raise_errors

    def initialize(token: nil, tenant: "tranquility", language: "en", cache: true, cache_store: nil, raise_errors: true)
      @token = token
      @tenant = tenant
      @language = language
      @cache = cache
      @cache_store = cache_store
      @raise_errors = raise_errors
    end

    def connection
      @connection ||= Faraday.new(BASE_URL) do |c|
        c.request :authorization, "Bearer", token if token

        if cache
          c.use :http_cache,
            store: cache_store,
            strategy: Faraday::HttpCache::Strategies::ByUrl,
            serializer: Marshal
        end

        c.request :json
        c.headers = DEFAULT_HEADERS
        c.response :raise_error if raise_errors
        c.response :json, content_type: "application/json"
      end
    end

    def method_missing(m, *args, &block)
      @path = Path.new(client: self).send(m.to_sym, *args)
    end
  end
end
