# Esirb

Esirb is a light wrapper around Faraday for the purposes of interacting with Eve Online's Swagger API.

I wanted something low maintenance, so this gem makes a few assumptions to let you dynamically generate any path that might end up on the ESI.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add esirb
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install esirb
```

## Usage


### Create a client
```ruby
client = Esirb::Client.new
```

A client holds no state from building paths or making requests, so one client can be shared between threads.
##### Create a client with a token
```ruby
client = Esirb::Client.new(token: "...")
```

ESI access tokens expire after about 20 minutes. If a client lives longer than that, pass something that returns the current token instead, such as a lambda. esirb calls it before every request:

```ruby
client = Esirb::Client.new(token: -> { character.access_token_refreshing_if_expired })
```

esirb doesn't refresh tokens itself: your app keeps the refresh token and does the refresh, and esirb only asks for the access token. If the callable returns `nil` or a blank string, the request raises `Esirb::Error` instead of being sent.

##### Identify your app
CCP asks every ESI client to send a User-Agent with the app's name and a way to contact you. Pass yours as `user_agent:`, and esirb adds its own name after it:

```ruby
client = Esirb::Client.new(user_agent: "mappy/1.2 (admin@example.com)")
client.user_agent # => "mappy/1.2 (admin@example.com) esirb/0.3.0 (+https://github.com/sicks/esirb)"
```

### Build the path, with any path parameters

Treat ESI static paths as method names, and path parameters as the arguments for those methods. Chain these methods to build the path to the desired ESI endpoint.

```ruby

path = client.route(3000142, 30002187)
path.string # => "/route/3000142/30002187"

path = client.ui.autopilot.waypoint
path.string # => "/ui/autopilot/waypoint"

path = client.characters(123456789).location
path.string # => "/characters/123456789/location"
```

Each call returns a new path, so you can reuse part of one:

```ruby
character = client.characters(123456789)
character.location.string # => "/characters/123456789/location"
character.skills.string   # => "/characters/123456789/skills"
```

Path params can be strings, symbols or integers, and are URL-encoded. Query params don't go in the path; pass them to the HTTP verb with `params:`.

Some ESI segments, like `freelance-jobs`, use hyphens, which Ruby method names can't contain. Call them with underscores instead:

```ruby
client.characters(123456789).freelance_jobs.string # => "/characters/123456789/freelance-jobs"
```

esirb keeps a list of ESI's hyphenated segments, and only those names are converted. Segments that really use underscores, like `system_kills`, stay as they are. For a segment esirb doesn't know about yet, add it exactly as written with `segment`:

```ruby
client.characters(123456789).segment("new-thing", 42).string # => "/characters/123456789/new-thing/42"
```

### Make the request, with any query parameters or body

Call an http verb, optionally passing `params`, `body` or `headers`.

```ruby
resp = path.get # => #<Faraday::Response>
resp.status # => 204
resp.body # => { "solar_system_id": 30000142 }

# check ESI documentation to know whether you need to pass query parameters, or a body
resp = path.post(params:, body:, headers:)
```

Headers passed to a verb are added to the client's default headers, and replace a default with the same name.

### All together now
```ruby
client = Esirb::Client.new
list_of_alliance_ids = client.alliances.get.body # => [...]
```

### Configuration

Set defaults for every new client once, for example in a Rails initializer:

```ruby
Esirb.configure do |config|
  config.user_agent = "mappy/1.2 (admin@example.com)"
  config.compatibility_date = "2026-08-18"
  config.cache_store = Rails.cache
end
```

Options passed to `Esirb::Client.new` override these for that client:

| Option | Default | Notes |
|---|---|---|
| `base_url` | `"https://esi.evetech.net"` | |
| `compatibility_date` | `"2026-08-18"` | Sent as `X-Compatibility-Date`, as a `"YYYY-MM-DD"` string or a `Date`. A newer date can change response shapes, so check your code against it before switching. Any date up to today works (ESI's day starts at 11:00 UTC), and ESI uses the latest published date on or before it. It can't be in the future, or `nil`: without a date, ESI uses its oldest behavior. |
| `tenant` | `"tranquility"` | Sent as `X-Tenant`. |
| `language` | `"en"` | Sent as `Accept-Language`. |
| `user_agent` | `nil` | Your app's name and contact info, sent before esirb's own User-Agent. |
| `cache_store` | `nil` | Where to cache responses. `nil` turns caching off; see [Caching](#caching). |
| `timeout` | `30` | Seconds to wait for a response. `nil` leaves it to the adapter. |
| `open_timeout` | `5` | Seconds to wait to open the connection. `nil` leaves it to the adapter. |
| `retries` | `2` | Times to retry a request that hit a 502, 503 or 504, a timeout or a connection failure; see [Retries](#retries). `0` turns retries off. |
| `faraday` | `nil` | A callable that customizes the Faraday connection; see [Customizing the connection](#customizing-the-connection). |

Setting `tenant` or `language` to `nil` leaves that header out. `token` is set per client only.

### Customizing the connection

esirb uses [Faraday](https://lostisland.github.io/faraday/). To add middleware, change the adapter or set other connection options, give `Esirb.configure` a `faraday` callable, or pass a block to a client. Both receive the Faraday connection builder after esirb has set up its own middleware:

```ruby
Esirb.configure do |config|
  config.faraday = ->(f) { f.response :logger, Rails.logger }
end

client = Esirb::Client.new { |f| f.adapter :net_http_persistent }
```

(`:net_http_persistent` comes from the `faraday-net_http_persistent` gem, which you'd add to your Gemfile.) The configured callable runs first, then the client's block. Middleware added this way sits closest to the network, so a logger sees the requests that actually go to ESI, not responses served from the cache.

### Caching

esirb caches responses only when you give it a `cache_store`, usually once in `Esirb.configure` so every client shares it. Any object with `read`, `write` and `delete` works, such as `Rails.cache` or another `ActiveSupport::Cache` store.

```ruby
Esirb.configure do |config|
  config.cache_store = ActiveSupport::Cache::RedisCacheStore.new(url: ENV["REDIS_URL"], namespace: "esirb", expires_in: 1.day)
end

Esirb::Client.new(cache_store: nil) # no caching for this client
```

Use a store that expires entries. Cache keys include the access token, and tokens change about every 20 minutes, so entries for old tokens are never read again. A store without expiry, including `Faraday::HttpCache::MemoryStore`, keeps them forever.

esirb follows ESI's cache headers:

- Responses are kept separate per URL, tenant, language, compatibility date and access token, so a shared store never serves one character's data to another.
- Authenticated responses are cached too. ESI marks them `private, max-age=5, must-revalidate`, so they're reused for 5 seconds and then revalidated, which returns a cheap `304 Not Modified` when nothing has changed.

### Errors

Error statuses from ESI raise a subclass of `Esirb::ResponseError`, with ESI's own message:

```ruby
begin
  client.universe.systems(1).get
rescue Esirb::NotFound => e
  e.message # => "404 System not found (GET https://esi.evetech.net/universe/systems/1)"
  e.status  # => 404
  e.body    # => { "error" => "System not found" }
  e.headers # => response headers, e.g. e.headers["X-ESI-Error-Limit-Remain"]
end
```

| Class | Raised for |
|---|---|
| `Esirb::BadRequest` | 400 |
| `Esirb::Unauthorized` | 401 |
| `Esirb::Forbidden` | 403 |
| `Esirb::NotFound` | 404 |
| `Esirb::RateLimited` | 420 (ESI's error limit) and 429 (rate limit). `retry_after` gives the seconds to wait, if ESI said. |
| `Esirb::ClientError` | Any other 4xx, and the parent of the classes above |
| `Esirb::BadGateway`, `Esirb::ServiceUnavailable`, `Esirb::GatewayTimeout` | 502, 503 and 504, after esirb's retries run out |
| `Esirb::ServerError` | Any other 5xx, and the parent of the three classes above |
| `Esirb::ConnectionFailed` | The connection to ESI failed, including TLS errors and timeouts while connecting |
| `Esirb::TimeoutError` | ESI connected but didn't answer within `timeout` |

Everything esirb raises is an `Esirb::Error`. When an error status is a normal answer, rescue its class. For example, ESI returns 404 for a character's fleet when they aren't in one:

```ruby
fleet = begin
  client.characters(123456789).fleet.get.body
rescue Esirb::NotFound
  nil
end
```

### Retries

ESI often answers with a 502, 503 or 504 that clears up within a second or two, so esirb retries those, along with timeouts and connection failures. By default it retries twice, waiting about half a second and then a second, with some randomness so many clients don't retry at the same moment.

- Only GET, HEAD, PUT and DELETE are retried. POST isn't, since repeating it might do something twice, like sending a mail.
- If ESI sends `Retry-After`, esirb waits that long instead. If it asks for more than 10 seconds, esirb raises straight away rather than tie up your process.
- Other errors, including 500, 4xx and the rate limits (420 and 429), aren't retried.

Set `retries` in `Esirb.configure` or per client to change the number, or to `0` to turn retries off. Worst case, a request takes about `(retries + 1) * timeout` seconds plus the waits, so lower `timeout` or `retries` together if that's too long.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/esirb.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
