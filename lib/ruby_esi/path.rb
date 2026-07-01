# frozen_string_literal: true

module RubyEsi
  class Path
    attr_reader :client, :string

    def initialize(client: nil)
      @client = client
      @string = ""
    end

    %i[get head delete trace post put patch].each do |verb|
      define_method verb do |params = {}, headers = {}|
        client.connection.send(verb, @string, params, headers)
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
