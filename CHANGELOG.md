## [Unreleased]

### Changed

- Requires Ruby 3.3 or newer.
- Each chained call returns a new, frozen `Esirb::Path`, so a partial path can be reused without changing it.
- Path params are URL-encoded. `nil`, blank, `.`, `..` and anything other than a string, symbol or integer raise `ArgumentError`.
- Keyword arguments in a path (`client.markets(1, type_id: 34)`) raise `ArgumentError`. Pass query params to the HTTP verb with `params:`.
- Only lowercase names that don't start with `to_` become path segments. Other missing methods raise `NoMethodError` as usual, so conversions like `Array#flatten` work.
- HTTP verbs raise `ArgumentError` on unknown options, and a `false` body is sent instead of dropped.
- `Esirb::Path.new` requires a client.

### Added

- Hyphenated ESI segments can be called with underscores: `client.characters(1).freelance_jobs` requests `/characters/1/freelance-jobs`. Only ESI's known hyphenated segments are converted.
- `#segment` on clients and paths adds a segment exactly as given, for segments esirb can't reach by method name.
- `rake esi:check_segments` compares esirb's list of hyphenated segments with ESI's OpenAPI spec.
- `respond_to?` reports path segment names.

### Removed

- The `trace` HTTP verb. ESI doesn't support it, and `trace` now works as a path segment.

## [0.1.0] - 2026-06-04

- Initial release
