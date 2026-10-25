# frozen_string_literal: true

require "rails/generators"
require "esirb"

module Esirb
  module Generators
    # rails generate esirb:install
    #
    # Writes config/initializers/esirb.rb with esirb's settings and a note on each. Rails finds this
    # by its path, so esirb has no Rails dependency, and nothing here loads outside a Rails generator.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)
      desc "Creates config/initializers/esirb.rb with esirb's settings for ESI."

      def create_initializer
        template "esirb.rb.tt", "config/initializers/esirb.rb"
      end

      private

      # For the User-Agent placeholder, e.g. "my-app" for a MyApp application.
      def app_name
        application = Rails.application if Rails.respond_to?(:application)
        return "my-app" unless application

        application.class.module_parent_name.underscore.dasherize
      end

      def defaults
        Configuration::DEFAULTS
      end
    end
  end
end
