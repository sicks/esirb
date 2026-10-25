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

### Pagination

ESI splits long lists into pages, using [one of three styles](https://developers.eveonline.com/docs/services/esi/pagination/x-pages/) depending on the route. You can tell which from the route's query parameters in ESI's API Explorer:

| The route takes | Style | Use | Typical routes |
|---|---|---|---|
| `page` | X-Pages | `get_all_pages` | market orders, assets, contracts, wallet journals |
| `before` and `after` | Cursor | `get_by_cursor` | freelance jobs, corporation projects, Paragon hub |
| `from_id` | From-ID | `get_from_id` | wallet transactions |

All three send their requests one at a time, never in parallel. Each request goes through esirb's cache, retries and error-limit guard like any other, and keeps the `params:` and `headers:` you pass. If any request fails, the error is raised and nothing is returned.

#### `get_all_pages`: numbered pages

```ruby
orders = client.markets(10000002).orders.get_all_pages(params: { type_id: 34 })
# => one array with every order from every page
```

Under the hood, that's the same as fetching the pages yourself:

```ruby
orders = client.markets(10000002).orders

first = orders.get(params: { type_id: 34, page: 1 })
total_pages = first.headers["X-Pages"].to_i
records = first.body

(2..total_pages).each do |page|
  response = orders.get(params: { type_id: 34, page: })
  # get_all_pages also checks this, and starts over from page 1 if it doesn't match:
  raise "data changed between pages" unless response.headers["Last-Modified"] == first.headers["Last-Modified"]

  records.concat(response.body)
end
```

Every page of one list should have the same `Last-Modified`. A different one means ESI refreshed the data partway through, so the pages would mix old and new records. `get_all_pages` then starts over from page 1 once, and raises `Esirb::PagesChanged` if it happens again. Fetching the whole list takes as many requests as there are pages, or up to twice that if it has to start over.

#### `get_by_cursor`: before and after cursors

These responses aren't a plain list. They're an object holding the records under a key that depends on the route (`freelance_jobs`, `projects`, `listings`...), plus a `cursor` with two values: `before`, pointing at older records, and `after`, pointing at newer ones. `get_by_cursor` finds the records' key for you. There are two ways to call it.

**Everything,** for a first sync:

```ruby
jobs, after = client.freelance_jobs.get_by_cursor
# jobs:  every record, oldest first
# after: save this to fetch only changes later
```

Done by hand, that's:

```ruby
freelance_jobs = client.freelance_jobs

response = freelance_jobs.get # no cursor: the most recent records
jobs = response.body["freelance_jobs"]
after = response.body.dig("cursor", "after") # where the list ends now; save it for later
before = response.body.dig("cursor", "before")

while before
  response = freelance_jobs.get(params: { before: })
  older = response.body["freelance_jobs"]
  break if older.empty?

  jobs = older + jobs # get_by_cursor also skips records it already has, matched by id
  before = response.body.dig("cursor", "before")
end
```

**Only what changed since** a saved `after`, to keep up to date:

```ruby
changed, after = client.freelance_jobs.get_by_cursor(after: saved_after)
```

Done by hand:

```ruby
changed = []
after = saved_after

loop do
  response = freelance_jobs.get(params: { after: })
  newer = response.body["freelance_jobs"]
  break if newer.empty?

  changed += newer # get_by_cursor also replaces records it already has with these newer copies
  after = response.body.dig("cursor", "after") || break
end
# Save `after` again for next time.
```

`after` and `before` values stay valid for days, according to CCP. Pass them back exactly as you got them, without trying to decode them. A record can show up on more than one page, for example when it changed while the pages were being fetched. `get_by_cursor` returns each record once, matched by its `id`: when following `before` toward older records it keeps the copy it already had, and when following `after` toward newer records it keeps the newest copy.

#### `get_from_id`: newest to oldest

```ruby
transactions = client.characters(123456789).wallet.transactions
all = transactions.get_from_id                             # newest first
newer = transactions.get_from_id(stop_at: newest_known_id) # only the ones after an ID you already have
```

Done by hand:

```ruby
records = transactions.get.body # the newest records, newest first

loop do
  from_id = records.last["transaction_id"]
  # The response starts with the from_id record again, followed by older ones.
  older = transactions.get(params: { from_id: }).body.reject { |record| record["transaction_id"] == from_id }
  break if older.empty?

  records.concat(older)
end
```

With `stop_at:`, `get_from_id` stops as soon as it reaches that ID and returns only the records before it. If the ID is on the first page, that's one request. Records are identified by `transaction_id`, which is what wallet transactions use. Pass `id_key:` if a route uses a different field.

### Configuration

In a Rails app, generate an initializer with each setting and a note on what it does:

```bash
bin/rails generate esirb:install
```

That writes `config/initializers/esirb.rb`, with your app's name in the User-Agent, esirb's current compatibility date pinned, and `Rails.cache` as the cache store. Edit the User-Agent's contact email before deploying.

Outside Rails, or to write it yourself, set defaults for every new client once:

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
| `Esirb::ErrorLimited` | 420: too many errors in ESI's error limit window. Every route is blocked until it resets. |
| `Esirb::TooManyRequests` | 429: a rate limit group is used up, after esirb's retries run out |
| `Esirb::RateLimited` | The parent of the two above. `retry_after` gives the seconds to wait, if ESI said. |
| `Esirb::ClientError` | Any other 4xx, and the parent of the classes above |
| `Esirb::BadGateway`, `Esirb::ServiceUnavailable`, `Esirb::GatewayTimeout` | 502, 503 and 504, after esirb's retries run out |
| `Esirb::ServerError` | Any other 5xx, and the parent of the three classes above |
| `Esirb::ConnectionFailed` | The connection to ESI failed, including TLS errors and timeouts while connecting |
| `Esirb::TimeoutError` | ESI connected but didn't answer within `timeout` |
| `Esirb::ErrorLimitReached` | Raised *without sending the request*, while ESI's error limit is nearly used up (needs a `cache_store`; see [Rate limits](#rate-limits)). `retry_after` gives the seconds until it resets. |

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
- A 429 is retried after its `Retry-After`, if that's 10 seconds or less. A 429 without `Retry-After`, which some routes send from inside EVE's servers, or one asking for longer, is raised straight away.
- When a failed response shows fewer than 20 errors left in ESI's [error limit](https://developers.eveonline.com/docs/services/esi/rate-limiting/), esirb stops retrying. Running out blocks every ESI route for your app until the window resets, and each failed retry counts as another error.
- Other errors, including 500, other 4xx and 420, aren't retried.

`retries` is the total for one request, whatever the reasons: with the default of 2, a request is sent at most 3 times. Set `retries` in `Esirb.configure` or per client to change the number, or to `0` to turn retries off. Worst case, a request takes about `(retries + 1) * timeout` seconds plus the waits, so lower `timeout` or `retries` together if that's too long.

### Rate limits

ESI limits requests in one of two ways, depending on the route ([details](https://developers.eveonline.com/docs/services/esi/rate-limiting/)). `Esirb::RateLimit` reads either from a response or an error:

```ruby
response = client.characters(123456789).location.get
limit = Esirb::RateLimit.new(response)
limit.group     # => "char-location"
limit.limit     # => 1200 tokens...
limit.window    # => ...per 900 seconds
limit.remaining # => 1195
limit.used      # => 2, what this request cost

# On routes still using the older error limit:
limit.error_limit_remaining # => 100 errors left in this window
limit.error_limit_reset     # => 46 seconds until it resets

# Errors carry the limits too:
begin
  client.characters(123456789).location.get
rescue Esirb::ResponseError => e
  e.rate_limit.remaining
end
```

Values a route doesn't send are `nil`. Errors cost more than successful requests (5 tokens for a 4xx against 2 for a 2xx), so avoid repeating requests that fail. CCP also recommends slowing down as `remaining` nears zero, and staggering scheduled work rather than running it all at the same minute.

#### Pausing before the error limit runs out

ESI's older error limit allows about 100 error responses a minute. Once it's used up, *every* ESI route returns 420 until the window resets, and repeatedly ignoring it can get an app banned. With a `cache_store`, esirb keeps track of it for you: when a response shows fewer than 20 errors left, every client sharing that store stops sending requests until the window resets, and raises `Esirb::ErrorLimitReached` instead.

```ruby
begin
  client.universe.systems(30000142).get
rescue Esirb::ErrorLimitReached => e
  e.retry_after # => 37, seconds until ESI's error limit resets
end
```

ESI counts the error limit per IP address, so esirb keeps one count per ESI host and tenant, shared by every client and process using the store. If several servers with different IP addresses share one store, an error burst on one pauses the others too, which errs on the side of sending less.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/esirb.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
