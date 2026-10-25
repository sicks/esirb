# frozen_string_literal: true

require_relative "lib/esirb/version"

Gem::Specification.new do |spec|
  spec.name = "esirb"
  spec.version = Esirb::VERSION
  spec.authors = ["sicks"]
  spec.email = ["esirb@sicks.dev"]

  spec.summary = "Ruby client for EVE Online's ESI API"
  spec.description = "A light client for EVE Online's ESI API. Build any endpoint's path from method calls, " \
                     "with caching, retries, rate and error limit handling, and pagination helpers built in."
  spec.homepage = "https://github.com/sicks/esirb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "lib/generators/**/*.tt", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.14"
  spec.add_dependency "faraday-http-cache", "~> 2.7"
end
