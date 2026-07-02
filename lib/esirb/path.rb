# frozen_string_literal: true

module Esirb
  class Path
    attr_reader :client, :string

    def initialize(client: nil)
      @client = client
      @string = ""
    end

    %i[get head delete trace post put patch].each do |verb|
      define_method verb do |**args|
        client.connection.send(verb, @string) do |req|
          req.params = args[:params] if args[:params]
          req.body = args[:body] if args[:body]
          req.headers = args[:headers] if args[:headers]
        end
      end
    end

    def method_missing(m, *args, &block)
      @string += "/#{m}"
      args.each do |arg|
        @string += "/#{arg}"
      end

      self
    end
  end
end
