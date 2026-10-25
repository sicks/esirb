# frozen_string_literal: true

require "erb"
require_relative "pagination"

module Esirb
  # An ESI endpoint path built by chaining method calls, sent with an HTTP verb method.
  #
  # Every call returns a new Path, so a partial path can be reused:
  #
  #   character = client.characters(123)
  #   character.location.to_s # => "/characters/123/location"
  #   character.skills.to_s   # => "/characters/123/skills"
  class Path
    include Pagination

    VERBS = %i[get head delete post put patch].freeze

    # Method names that become path segments. Conversion hooks like to_ary and to_str are left to Ruby.
    SEGMENT_NAME = /\A(?!to_)[a-z][a-z0-9_]*\z/
    SEGMENT_TYPES = [String, Symbol, Integer].freeze

    # ESI segments with hyphens, which can't be Ruby method names. Calling the underscored name
    # (client.freelance_jobs) sends the hyphenated segment. Segments keep their spelling across
    # compatibility dates, so this covers every date. `rake esi:check_segments` compares it with
    # ESI's OpenAPI spec for each date.
    HYPHENATED_SEGMENTS = %w[
      access-lists
      compatibility-dates
      freelance-jobs
      mercenary-dens
      mercenary-tactical-operations
      military-campaigns
      paragon-hub
      recommended-fit
      sovereignty-hubs
    ].to_h { |segment| [segment.tr("-", "_"), segment] }.freeze

    NO_BODY = Object.new.freeze
    private_constant :NO_BODY

    def self.segment_name?(name)
      SEGMENT_NAME.match?(name.to_s)
    end

    attr_reader :client

    def initialize(client:, segments: [])
      raise ArgumentError, "client is required" if client.nil?

      @client = client
      @segments = segments.freeze
      @path = segments.map { |segment| "/#{segment}" }.join.freeze
      freeze
    end

    # get, head, delete, post, put and patch send the request and return the Faraday response.
    # params: become the query string, body: is sent as JSON, and headers: are added to the
    # client's defaults, replacing any with the same name.
    VERBS.each do |verb|
      define_method verb do |params: nil, body: NO_BODY, headers: nil|
        client.connection.public_send(verb, to_s) do |req|
          req.params.update(params) if params
          req.body = body unless body.equal?(NO_BODY)
          req.headers.update(headers) if headers
        end
      end
    end

    # The path, e.g. "/characters/123/location".
    def to_s
      @path
    end

    # Adds a segment and its path params to a copy of this path, exactly as given. Use it for
    # segments that can't be reached by method name.
    def segment(name, *params)
      self.class.new(client:, segments: @segments + [name, *params].map { |value| encode(value) })
    end

    def method_missing(name, *params, **kwargs)
      return super unless self.class.segment_name?(name)
      if kwargs.any?
        raise ArgumentError, "path segments only take positional params; pass query params to the HTTP verb as params:"
      end

      segment(HYPHENATED_SEGMENTS.fetch(name.to_s, name), *params)
    end

    def respond_to_missing?(name, include_private = false)
      self.class.segment_name?(name) || super
    end

    private

    def encode(value)
      unless SEGMENT_TYPES.any? { |type| value.is_a?(type) }
        raise ArgumentError, "path segments must be strings, symbols or integers, got #{value.inspect}"
      end

      text = value.to_s
      raise ArgumentError, "path segments can't be #{text.inspect}" if ["", ".", ".."].include?(text)

      ERB::Util.url_encode(text)
    end
  end
end
