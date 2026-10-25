## [Unreleased]

### Changed

- Requires Ruby 3.3 or newer.
- GET, HEAD, PUT and DELETE requests are retried up to twice after a 502, 503 or 504, a timeout or a connection failure, honoring `Retry-After`.
- 420 raises `Esirb::ErrorLimited` and 429 raises `Esirb::TooManyRequests`, both subclasses of `Esirb::RateLimited`.
- A 429 is retried after its `Retry-After` when that's 10 seconds or less, and nothing is retried once fewer than 20 errors are left in ESI's error limit window.
- 502, 503 and 504 raise `Esirb::BadGateway`, `Esirb::ServiceUnavailable` and `Esirb::GatewayTimeout`, which are subclasses of `Esirb::ServerError`.
- Requests time out after 30 seconds waiting for a response and 5 seconds opening the connection. Before, they used the adapter's defaults (60 seconds each for Net::HTTP).
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
- `compatibility_date` can't be `nil`, since a request without a date gets ESI's oldest behavior, and must be a `YYYY-MM-DD` string or a `Date` that isn't in the future (ESI's day starts at 11:00 UTC). These are checked when the client is created, instead of failing with a 400 on the first request.
- A client builds its Faraday connection when it's created instead of on first use, and keeps no state from building paths, so one client can be shared between threads.
- Responses are cached only when a `cache_store` is set, in `Esirb.configure` or per client. Before, every client cached in its own unbounded in-memory store by default.
- The cache stores raw response bodies as JSON instead of Marshal data.
- Array query params are sent as repeated keys (`label_ids=1&label_ids=2`), which is what ESI reads, instead of Faraday's Rails-style `label_ids[]=1&label_ids[]=2`.
- Responses with any JSON content type are parsed, including `+json` types like ESI's `application/openapi+json`. Before, only `application/json` was.
- Errors are esirb's own classes instead of Faraday's: error statuses raise `Esirb::ResponseError` subclasses, and connection failures and timeouts raise `Esirb::ConnectionFailed` and `Esirb::TimeoutError`, with the Faraday error as the `cause`. Code that rescues `Faraday::Error` needs to rescue `Esirb::Error` instead.

### Fixed

- A cache store shared between clients could serve one token's response to another, or a response in the wrong language, tenant or compatibility date. Cache entries are now keyed on the URL plus ESI's `Vary` headers and the token. Entries written by older versions aren't read, so the cache starts empty after upgrading.

### Added

- `Esirb.configure` sets defaults for new clients: `base_url`, `compatibility_date`, `tenant`, `language`, `user_agent` and `cache_store`. Each can also be passed to `Esirb::Client.new`.
- Authenticated responses (`Cache-Control: private`) are cached per access token.
- `rails generate esirb:install` writes `config/initializers/esirb.rb` with esirb's settings. esirb doesn't depend on Rails; the generator only loads when Rails runs it.
- Pagination helpers for ESI's three pagination styles: `get_all_pages` (`page` and `X-Pages`, restarting if the data changes partway through), `get_by_cursor` (`before`/`after` cursors, returning the `after` token to save) and `get_from_id` (`from_id`).
- With a `cache_store`, esirb stops sending requests while ESI's error limit is nearly used up (fewer than 20 errors left), across every client and process sharing the store, and raises `Esirb::ErrorLimitReached` with `retry_after` instead.
- `Esirb::RateLimit` reads ESI's rate limit and error limit headers from a response, and `Esirb::ResponseError#rate_limit` from an error.
- A `retries` option (default 2; 0 turns retries off).
- `timeout` and `open_timeout` options, and a `faraday` option or client block for adding middleware, changing the adapter or setting other connection options.
- `token:` accepts a callable, which is called before every request, so a long-lived client can use your app's refreshed access tokens. A string still works as before.
- An error hierarchy under `Esirb::Error`: `BadRequest`, `Unauthorized`, `Forbidden`, `NotFound`, `RateLimited` (with `retry_after`), `ClientError` and `ServerError`, each exposing `status`, `body`, `headers` and `response`.
- `military_campaigns`, `paragon_hub` and `recommended_fit` reach their hyphenated ESI segments, and `rake esi:check_segments` now checks every compatibility date.
- `user_agent:` client option for your app's name and contact info, sent before esirb's own User-Agent.
- Hyphenated ESI segments can be called with underscores: `client.characters(1).freelance_jobs` requests `/characters/1/freelance-jobs`. Only ESI's known hyphenated segments are converted.
- `#segment` on clients and paths adds a segment exactly as given, for segments esirb can't reach by method name.
- `rake esi:check_segments` compares esirb's list of hyphenated segments with ESI's OpenAPI spec.
- `respond_to?` reports path segment names.

### Removed

- `Esirb::Client#path`, which held the last path built. `client.path` is now an ordinary `/path` segment.
- The `raise_errors:` client option. Error statuses always raise; rescue the `Esirb::ResponseError` subclass when a status is expected, and use `e.response`, `e.status` or `e.body` to inspect it.
- The `cache:` client option. Pass `cache_store: nil` to turn caching off for one client.
- `Esirb::Client::BASE_URL` and `Esirb::Client::DEFAULT_HEADERS`. Use `Esirb.configuration` or the client's readers (`base_url`, `compatibility_date`, ...).
- The `trace` HTTP verb. ESI doesn't support it, and `trace` now works as a path segment.

## [0.1.0] - 2026-06-04

- Initial release
