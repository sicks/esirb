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
##### Create a client with a token
```ruby
client = Esirb::Client.new(token: "...")
```

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

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/esirb.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
