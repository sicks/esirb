# frozen_string_literal: true

# A light Ruby client for EVE Online's ESI API.
module Esirb
  # App-wide defaults for new clients. Set them once with Esirb.configure; options passed to
  # Esirb::Client.new override them for that client.
  class Configuration
    DEFAULTS = {
      base_url: "https://esi.evetech.net",
      # Part of the API contract: a newer date can change response shapes. Only move it in a
      # release that has been checked against that date.
      compatibility_date: "2026-08-18",
      tenant: "tranquility",
      language: "en",
      # Your app's name, version and contact info, e.g. "mappy/1.2 (admin@example.com)".
      user_agent: nil,
      # Where to cache responses, e.g. Rails.cache. Anything with read, write and delete works.
      # nil turns caching off.
      cache_store: nil,
      # Seconds to wait for a response, and to open the connection. nil leaves it to the adapter.
      timeout: 30,
      open_timeout: 5,
      # Called with the Faraday connection builder after esirb's own setup, to add middleware,
      # change the adapter or set other connection options.
      faraday: nil
    }.freeze

    attr_accessor(*DEFAULTS.keys)

    def initialize
      DEFAULTS.each { |name, value| public_send(:"#{name}=", value) }
    end

    def to_h
      DEFAULTS.keys.to_h { |name| [name, public_send(name)] }
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
