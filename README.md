# RubyLLM Responses API

A [RubyLLM](https://github.com/crmne/ruby_llm) provider for OpenAI's [Responses API](https://platform.openai.com/docs/api-reference/responses).

## Installation

```ruby
gem 'ruby_llm-responses_api'
```

## Quick Start

```ruby
require 'ruby_llm-responses_api'

RubyLLM.configure do |config|
  config.openai_api_key = ENV['OPENAI_API_KEY']
end

chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)
response = chat.ask("Hello!")
puts response.content
```

## Multi-turn Conversations

Conversations automatically chain via `previous_response_id`:

```ruby
chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)
chat.ask("My name is Alice.")
chat.ask("What's my name?")  # => "Your name is Alice."
```

## Rails Integration

For persistent conversations that survive app restarts:

**1. Add migration:**

```ruby
class AddResponseIdToMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :messages, :response_id, :string
    add_index :messages, :response_id
  end
end
```

**2. Enable extensions in initializer:**

```ruby
# config/initializers/ruby_llm.rb
RubyLLM.configure do |config|
  config.openai_api_key = ENV['OPENAI_API_KEY']
end

RubyLLM::Providers::OpenAIResponses.apply_active_record_extensions!
```

**3. Use as normal:**

```ruby
# Day 1
chat = Chat.create!(model_id: 'gpt-4o-mini', provider: :openai_responses)
chat.ask("My name is Alice.")

# Day 2 (after app restart)
chat = Chat.find(1)
chat.ask("What's my name?")  # => "Alice" - context preserved!
```

## Features

### Streaming

```ruby
chat.ask("Write a poem") { |chunk| print chunk.content }
```

### Tools

```ruby
class WeatherTool < RubyLLM::Tool
  description "Get weather for a location"
  param :city, type: "string", desc: "City name"

  def execute(city:)
    "#{city}: Sunny, 72°F"
  end
end

chat.with_tool(WeatherTool)
chat.ask("Weather in Tokyo?")
```

### Web Search

```ruby
chat.with_params(tools: [{ type: 'web_search_preview' }])
chat.ask("Latest news about Ruby?")
```

### Structured Output

```ruby
schema = {
  type: 'object',
  properties: { name: { type: 'string' }, age: { type: 'integer' } },
  required: %w[name age],
  additionalProperties: false
}

chat.with_schema(schema)
response = chat.ask("Generate a person")
response.content  # => {"name" => "Alice", "age" => 28}
```

### Vision

```ruby
content = RubyLLM::Content.new("Describe this", images: ["photo.jpg"])
chat.ask(content)
```

## Supported Models

- **GPT-4o**: `gpt-4o`, `gpt-4o-mini`
- **GPT-4.1**: `gpt-4.1`, `gpt-4.1-mini`, `gpt-4.1-nano` (1M context)
- **O-series**: `o1`, `o3`, `o3-mini`, `o4-mini` (reasoning)

## License

MIT
