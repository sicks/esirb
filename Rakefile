# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]

namespace :esi do
  desc "Compare Esirb::Path::HYPHENATED_SEGMENTS with the segments in ESI's OpenAPI spec"
  task :check_segments do
    require "json"
    require_relative "lib/esirb"

    client = Esirb::Client.new(cache: false)
    date = Esirb::Client::DEFAULT_HEADERS["X-Compatibility-Date"]
    # ESI serves the spec as application/openapi+json, which esirb doesn't parse yet (MP-231).
    spec = JSON.parse(client.meta.segment("openapi.json").get(params: { compatibility_date: date }).body)
    segments = spec["paths"].keys.flat_map { |path| path.split("/") }.reject { |s| s.empty? || s.start_with?("{") }
    hyphenated = segments.select { |s| s.include?("-") }.uniq.sort

    listed = Esirb::Path::HYPHENATED_SEGMENTS.values.sort
    missing = hyphenated - listed
    stale = listed - hyphenated

    puts "ESI spec for compatibility date #{date}: #{hyphenated.size} hyphenated segments"
    puts "Missing from HYPHENATED_SEGMENTS: #{missing.join(", ")}" if missing.any?
    puts "Listed but no longer in ESI: #{stale.join(", ")}" if stale.any?
    abort if missing.any? || stale.any?

    puts "HYPHENATED_SEGMENTS is up to date."
  end
end
