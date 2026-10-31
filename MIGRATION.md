# Migrating from 0.x to 1.0

Version 1.0 uses RubyLLM's native OpenAI Responses protocol and adds server-side conversation state, WebSocket transport, containers and response lifecycle helpers. Keep `provider: :openai_responses` to retain this gem's behavior.

This guide covers application changes from `ruby_llm-responses_api` 0.x to 1.0.

## 1. Upgrade the runtime and dependencies

The supported versions are:

| Dependency | Requirement |
| --- | --- |
| Ruby | 4.x only: `>= 4.0, < 5.0` |
| RubyLLM | `>= 2.1.1, < 2.2` |
| ruby_llm-responses_api | 1.0.x |
| websocket-client-simple | Optional; required for WebSocket transport |

For Rails applications still on RubyLLM 1.x, first follow the upstream [1.x to 2.0 guide](https://github.com/crmne/ruby_llm/blob/v2.0.0/docs/_reference/upgrading.md), then the [2.0 to 2.1 guide](https://rubyllm.com/upgrading/). Complete the database migration and cleanup steps for each release before moving to the next. The upstream 2.1 upgrade generator does not include the earlier upgrade helpers. This gem's 0.x implementation cannot be loaded alongside RubyLLM 2.x; account for that in the intermediate upgrade environment.

Set Ruby 4 in your runtime configuration, container image and CI. For mise:

```toml
[tools]
ruby = "4.0"
```

Use these final dependency constraints in your application's `Gemfile`:

```ruby
ruby '>= 4.0', '< 5.0'

gem 'ruby_llm', '~> 2.1.1'
gem 'ruby_llm-responses_api', '~> 1.0.0'

# Add when using WebSocket transport:
gem 'websocket-client-simple', '~> 0.8'
```

Then resolve the new bundle:

```sh
bundle update ruby_llm ruby_llm-responses_api
```

## 2. Keep the provider and configuration

The require path, OpenAI credentials and provider name stay the same:

```ruby
require 'ruby_llm-responses_api'

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch('OPENAI_API_KEY')
end

chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses)
response = chat.ask('Hello!')
puts response.content
```

Keep existing `openai_responses` provider values in persisted chats and model records. Switching to `provider: :openai` selects RubyLLM's native stateless behavior and does not enable this gem's automatic chaining or transport helpers.

Model capabilities, limits and pricing now come from the native OpenAI catalog. For a model absent from that catalog, pass `assume_model_exists: true` with an explicit provider. Remove application code that calls the old `ModelRegistry.register_all!`.

## 3. Update chat and message APIs

| Before | After |
| --- | --- |
| `chat.with_params(...)` | `chat.with_provider_options(...)` |
| `chat.with_tool(MyTool)` | `chat.with_tools(MyTool)` |
| `chat.on_tool_call { ... }` | `chat.before_tool_call { ... }` |
| `chat.on_tool_result { ... }` | `chat.after_tool_result { ... }` |
| `response.input_tokens` | `response.tokens.input` |
| `response.output_tokens` | `response.tokens.output` |
| `response.cached_tokens` | `response.tokens.cache_read` |
| `response.cache_creation_tokens` | `response.tokens.cache_write` |
| `response.model_id` | `response.model` |
| Structured `response.content` | `response.parsed` |
| `RubyLLM::Content` attachments | `chat.ask('Describe', with: files_or_urls)` |
| `Chat.create!(model_id: ..., provider: ...)` | `Chat.create!(model: ..., provider: ...)` |

`response.content` is a string even when a schema is configured. Read structured data through `response.parsed`:

```ruby
chat.with_schema(
  type: 'object',
  properties: { answer: { type: 'string' } },
  required: ['answer'],
  additionalProperties: false
)
response = chat.ask('Give a short answer.')
puts response.parsed.fetch('answer')
```

Pass attachments directly to `ask`:

```ruby
chat.ask('Summarize this document.', with: ['report.pdf'])
chat.ask('Describe this image.', with: ['photo.png'])
```

`with_provider_options` replaces the current options hash. Preserve other options when changing one:

```ruby
chat.with_provider_options(chat.provider_options.merge(store: false))
```

## 4. Check conversation state

Automatic chaining remains the default for `:openai_responses`. Requests use `store: true`; the next request sends only messages after the last stored assistant response, with its ID in `previous_response_id`. Current system instructions are sent again on each request. This applies to sync HTTP, HTTP streaming and WebSocket calls.

```ruby
chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses)
first = chat.ask('My name is Alice.')
puts first.response_id
chat.ask('What is my name?')
```

Remove workarounds that manually trim history or patch `format_input` for issue #10. History filtering is handled by the new protocol. Keep complete local conversation history so stateless replay remains possible.

To disable automatic chaining and replay the local history:

```ruby
chat.with_provider_options(store: false)
response = chat.ask('Continue using the local history.')
```

In this mode, returned messages have no automatic chaining `response_id`. The native protocol preserves reasoning data for replay. If needed for diagnostics, the API's returned ID is available at `response.raw.body['id']`.

To start a fresh stored chain from the full local history, explicitly set `previous_response_id: nil` for that request. Remove the override before the next request:

```ruby
options = chat.provider_options.except(:previous_response_id).merge(store: true)
chat.with_provider_options(options.merge(previous_response_id: nil))
chat.ask('Start a fresh chain using this history.')
chat.with_provider_options(options)
```

An explicit external `previous_response_id` can resume a stored response in a new chat. Supply only the new local input for that parent; do not also import its entire old history.

## 5. Update tools and callbacks

Custom function tools use RubyLLM's native declarations:

```ruby
class Weather < RubyLLM::Tool
  description 'Get the weather for a city'
  parameter :city, type: 'string', description: 'City name'

  def execute(city:)
    "Sunny in #{city}"
  end
end

chat.with_tools(Weather)
```

Replace the old `param` declaration with `parameter`, and `desc:` with `description:`. Native function definitions default to non-strict mode. To retain strict definitions, add `provider_options strict: true` to the tool class.

Built-in tool hash builders remain available:

```ruby
tool = RubyLLM::ResponsesAPI::BuiltInTools.shell
chat.with_provider_options(tools: [tool])
```

For tools supported by RubyLLM's native helpers, you can also use:

```ruby
chat.with_provider_tools(:web_search, :code_execution)
```

Rename the callbacks:

```ruby
chat.before_tool_call { |call| puts "#{call.name}: #{call.id}" }
chat.after_tool_result { |result| puts result.inspect }
```

For built-in server tools, callbacks run when the final assistant message is added. They report completed work, not live progress, and retain this gem's result hash format. Local function tools keep RubyLLM's own callback arguments.

Use `response.server_tool_calls` for native server tool records. Each record's `raw` retains its provider-specific fields. Existing parsers such as `BuiltInTools.parse_shell_call_results(response.raw.body['output'])` remain available.

For this provider, `response.raw.body` contains the final Responses object in all three transports. For streaming, this is a reconstructed body from the final response event, rather than the SSE wire body. Remove old patches that reconstruct built-in tool metadata or forward `response_id` through the global accumulator.

## 6. Move raw-input batch calls to ResponsesAPI

The gem no longer overrides `RubyLLM.batch`. Rename the factories used by the existing raw-input workflow:

| Before | After |
| --- | --- |
| `RubyLLM.batch(model: ..., provider: ...)` | `RubyLLM::ResponsesAPI.batch(model: ..., provider: ...)` |
| `RubyLLM.batch(id: ...)` | `RubyLLM::ResponsesAPI.batch(id: ...)` |
| `RubyLLM.batches(...)` | `RubyLLM::ResponsesAPI.batches(...)` |

```ruby
batch = RubyLLM::ResponsesAPI.batch(model: 'gpt-4o')
batch.add('What is Ruby?', id: 'ruby')
batch.create!
batch.wait!
puts batch.results.fetch('ruby').content

# Resume or list existing batches:
RubyLLM::ResponsesAPI.batch(id: 'batch_existing')
RubyLLM::ResponsesAPI.batches
```

The helper defaults to `provider: :openai_responses`. RubyLLM's separate native `RubyLLM.batch(chats)` API remains available for its persisted-chat batch workflow.

## 7. Retain Rails response IDs

Complete RubyLLM's own schema upgrades first. Keep the string `response_id` column on your application message table. If it is already present, this gem needs no additional schema change. If it is absent:

```sh
bin/rails generate migration AddResponseIdToMessages response_id:string
bin/rails db:migrate
```

Substitute your actual message table name when using a custom model. The column is optional, but automatic chaining cannot resume across a database reload without it.

Update chat creation to use `model:`:

```ruby
chat = Chat.create!(model: 'gpt-4o', provider: :openai_responses)
chat.ask('My name is Alice.')

# After a restart:
Chat.find(chat.id).ask('What is my name?')
```

The extension preserves native persistence of usage, reasoning, citations, attachments and tool records, while adding `response_id`. If using ActiveRecord outside Rails, apply the extension after loading ActiveRecord:

```ruby
require 'active_record'
RubyLLM::Providers::OpenAIResponses.apply_active_record_extensions!
```

## 8. Update WebSocket options and error handling

Add `websocket-client-simple` to your application's bundle, then rename `with_params`:

```ruby
chat.with_provider_options(transport: :websocket)
chat.ask('Hello') { |chunk| print chunk.content }
```

Additional chat headers are sent in the handshake. Changing them reconnects the transport. A disconnect before completion now raises `RubyLLM::ResponsesAPI::WebSocket::ConnectionError` instead of returning a partial answer as a successful response. Handle that exception in the application's transport failure path.

Standalone `RubyLLM::ResponsesAPI::WebSocket` remains available. Its `tools:` argument accepts raw Responses API tool hashes; use `BuiltInTools` to build those hashes.

## 9. Remove patches against retired internals

These helpers remain available under `RubyLLM::ResponsesAPI`: `Batch`, `Batches`, `BuiltInTools`, `State`, `Background`, `Compaction`, `Containers` and `WebSocket`.

The old provider `Chat`, `Streaming`, `Media`, `Models`, `Tools` and `Capabilities` modules have been removed. Update direct requires and monkey patches against those modules. Rendering and parsing now use the native RubyLLM protocol; this gem's accumulator is scoped to its own provider.

## Verify the application upgrade

Before deploying, check the application paths you use:

- A sync and a streamed two-turn chat retain `response_id` and send only new input on the second turn.
- A tool call executes and its result reaches the follow-up request.
- Structured output uses `response.parsed`; token displays use `response.tokens`.
- A persisted chat can resume after a fresh database load.
- Raw-input batch calls use `RubyLLM::ResponsesAPI`.
- WebSocket disconnects reach the application's failure handler.

For contributors, `bundle exec rake` runs this repository's tests and RuboCop on Ruby 4. Historic VCR recordings remain unchanged and use a compatibility matcher for equivalent 0.x request shapes. Separate WebMock tests assert the new payload, state, persistence and WebSocket behavior.

The optional live WebSocket check sends real requests using the configured OpenAI account:

```sh
bundle exec rspec spec/integration/websocket_spec.rb --tag live_ws
```

Set `OPENAI_API_KEY` before running that check.
