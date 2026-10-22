## [Unreleased]

### Changed

- Requires Ruby 3.3 or newer.
- The default ESI compatibility date is `2026-08-18` (was `2026-06-09`). Set `compatibility_date` to keep the old one.
- Headers and params passed to an HTTP verb are merged with the defaults instead of replacing them. A per-request header replaces a default with the same name.
- Requests no longer send empty `If-Modified-Since` and `If-None-Match` headers.
- The User-Agent is `esirb/<version> (+https://github.com/sicks/esirb)` instead of Faraday's.
- Each chained call returns a new, frozen `Esirb::Path`, so a partial path can be reused without changing it.
- Path params are URL-encoded. `nil`, blank, `.`, `..` and anything other than a string, symbol or integer raise `ArgumentError`.
- Keyword arguments in a path (`client.markets(1, type_id: 34)`) raise `ArgumentError`. Pass query params to the HTTP verb with `params:`.
- Only lowercase names that don't start with `to_` become path segments. Other missing methods raise `NoMethodError` as usual, so conversions like `Array#flatten` work.
- HTTP verbs raise `ArgumentError` on unknown options, and a `false` body is sent instead of dropped.
- `Esirb::Path.new` requires a client.
- `Esirb::Client.new` raises `ArgumentError` on unknown options.

### Fixed

- A cache store shared between clients could serve one token's response to another, or a response in the wrong language, tenant or compatibility date. Cache entries are now keyed on the URL plus ESI's `Vary` headers and the token. Entries written by older versions aren't read, so the cache starts empty after upgrading.

### Added

- `Esirb.configure` sets defaults for new clients: `base_url`, `compatibility_date`, `tenant`, `language`, `user_agent` and `raise_errors`. Each can also be passed to `Esirb::Client.new`.
- `military_campaigns`, `paragon_hub` and `recommended_fit` reach their hyphenated ESI segments, and `rake esi:check_segments` now checks every compatibility date.
- `user_agent:` client option for your app's name and contact info, sent before esirb's own User-Agent.
- Hyphenated ESI segments can be called with underscores: `client.characters(1).freelance_jobs` requests `/characters/1/freelance-jobs`. Only ESI's known hyphenated segments are converted.
- `#segment` on clients and paths adds a segment exactly as given, for segments esirb can't reach by method name.
- `rake esi:check_segments` compares esirb's list of hyphenated segments with ESI's OpenAPI spec.
- `respond_to?` reports path segment names.

### Removed

- `Esirb::Client::BASE_URL` and `Esirb::Client::DEFAULT_HEADERS`. Use `Esirb.configuration` or the client's readers (`base_url`, `compatibility_date`, ...).
- The `trace` HTTP verb. ESI doesn't support it, and `trace` now works as a path segment.

## [0.1.0] - 2026-06-04

- Initial release
