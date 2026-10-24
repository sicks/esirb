# frozen_string_literal: true

require "date"

module Esirb
  # Checks the date sent as X-Compatibility-Date. Any date from ESI's oldest supported one to today
  # works; ESI uses the latest published compatibility date on or before it. The oldest supported
  # date isn't checked here, since CCP can raise it.
  module CompatibilityDate
    FORMAT = /\A\d{4}-\d{2}-\d{2}\z/

    # Returns the date as a YYYY-MM-DD string, or raises ArgumentError.
    def self.parse(value)
      if value.nil?
        raise ArgumentError, "compatibility_date can't be nil, since ESI would then use its oldest behavior. " \
                             'Pass that date ("2020-01-01") explicitly if that\'s what you want.'
      end

      date = to_date(value)
      raise ArgumentError, "compatibility_date #{date} is in the future; ESI's current date is #{today}" if date > today

      date.strftime("%Y-%m-%d")
    end

    # ESI's date rolls over at 11:00 UTC.
    def self.today
      (Time.now.utc - (11 * 60 * 60)).to_date
    end

    def self.to_date(value)
      # DateTime is a Date too. to_date drops its time, so a later hour today isn't counted as the future.
      return value.to_date if value.is_a?(Date)

      text = value.to_s
      return Date.iso8601(text) if text.match?(FORMAT) && Date.valid_date?(*text.split("-").map(&:to_i))

      raise ArgumentError, "compatibility_date must be a YYYY-MM-DD date, got #{value.inspect}"
    end
    private_class_method :to_date
  end
end
