# RubyLLM 1.17 Reference

This reference covers using `ruby_llm-responses_api` with RubyLLM 1.17, where OpenAI Responses API support is native to RubyLLM.

Use RubyLLM's built-in `:openai` provider. The old `:openai_responses` provider is only a compatibility fallback for older RubyLLM versions.

## Installation

```ruby
gem 'ruby_llm', '~> 1.17'
gem 'ruby_llm-responses_api'
```

```ruby
require 'ruby_llm-responses_api'

RubyLLM.configure do |config|
  config.openai_api_key = ENV['OPENAI_API_KEY']
end
```

## Chat

```ruby
chat = RubyLLM.chat(model: 'gpt-5.5', provider: :openai)
response = chat.ask('Hello!')
puts response.content
```

RubyLLM 1.17 handles the native Responses wire format. This gem adds advanced Responses features around that native implementation.

## Stateful Responses

This gem stores each OpenAI response ID on assistant messages and sends the next turn with `previous_response_id`.

```ruby
chat = RubyLLM.chat(model: 'gpt-5.5', provider: :openai)
chat.ask('My name is Alice.')
chat.ask("What's my name?")
```

For Rails persistence, add a nullable `response_id` column to messages:

```ruby
class AddResponseIdToMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :messages, :response_id, :string
  end
end
```

## Built-In Tool Helpers

Pass native Responses tools through `with_params(tools: ...)`.

```ruby
chat = RubyLLM.chat(model: 'gpt-5.5', provider: :openai)
chat.with_params(tools: [
  RubyLLM::ResponsesAPI::BuiltInTools.web_search(search_context_size: 'high')
])
chat.ask('What changed in Ruby recently?')
```

Available helpers include:

- `web_search`
- `web_search_preview`
- `file_search`
- `code_interpreter`
- `image_generation`
- `mcp`
- `computer_use`
- `shell`
- `apply_patch`

## Tool Activity Callbacks

Server-side built-in tools are surfaced through the same callbacks as local RubyLLM tools.

```ruby
chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai)
chat.with_params(tools: [{ type: 'web_search' }])

chat.before_tool_call { |tool_call| puts "calling #{tool_call.name}" }
chat.after_tool_result { |result| puts "status=#{result[:status]}" }

chat.ask('Find the latest Ruby release.')
```

## Background Responses

```ruby
chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai)
chat.with_params(background: true)
response = chat.ask('Analyze this large dataset...')

provider = chat.instance_variable_get(:@provider)
result = provider.poll_response(response.response_id, interval: 2.0)
```

The OpenAI provider is extended with:

- `retrieve_response`
- `cancel_response`
- `delete_response`
- `list_input_items`
- `poll_response`

## Containers

```ruby
chat = RubyLLM.chat(model: 'gpt-5.5', provider: :openai)
provider = chat.instance_variable_get(:@provider)

container = provider.create_container(
  name: 'analysis',
  expires_after: { anchor: 'last_active_at', minutes: 60 },
  memory_limit: '4g'
)

tool = RubyLLM::ResponsesAPI::BuiltInTools.shell(container_id: container['id'])
chat.with_params(tools: [tool])
chat.ask('Run the analysis script.')
```

Container helpers:

- `create_container`
- `retrieve_container`
- `delete_container`
- `list_container_files`
- `retrieve_container_file`
- `retrieve_container_file_content`

## Server-Side Compaction

```ruby
chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai)
chat.with_params(
  **RubyLLM::ResponsesAPI::Compaction.compaction_params(compact_threshold: 150_000)
)
```

Explicit provider helpers:

```ruby
provider = chat.instance_variable_get(:@provider)

provider.compact_response(
  model: 'gpt-5.5',
  input: [{ type: 'message', role: 'user', content: 'Summarize this session.' }]
)

provider.count_input_tokens(model: 'gpt-5.5', input: 'Tell me a joke.')
```

## Batch API

```ruby
batch = RubyLLM.batch(model: 'gpt-4o', provider: :openai)
batch.add('What is Ruby?')
batch.add('Translate: hello', id: 'translate_1')
batch.create!
batch.wait!(interval: 60)

results = batch.results
puts results['translate_1'].content
```

Resume or list batches:

```ruby
batch = RubyLLM.batch(id: 'batch_abc123', provider: :openai)
RubyLLM.batches(provider: :openai)
```

## WebSocket Transport

Add `websocket-client-simple` when using WebSocket mode:

```ruby
gem 'websocket-client-simple'
```

```ruby
chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai)
chat.with_params(transport: :websocket)

chat.ask('Hello!')
chat.ask("What's 2+2?")
```

Direct access is also available:

```ruby
ws = RubyLLM::ResponsesAPI::WebSocket.new(api_key: ENV['OPENAI_API_KEY'])
ws.connect
ws.create_response(model: 'gpt-4o', input: [{ type: 'message', role: 'user', content: 'Hello' }])
ws.disconnect
```

## Legacy Provider

For RubyLLM 1.17, prefer `provider: :openai`.

The `:openai_responses` provider path is retained only for older RubyLLM releases that do not have native Responses protocol support.
