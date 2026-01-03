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

All standard RubyLLM features work as expected (streaming, tools, vision, structured output).

## Stateful Conversations

Conversations automatically chain via `previous_response_id`:

```ruby
chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)
chat.ask("My name is Alice.")
chat.ask("What's my name?")  # => "Your name is Alice."
```

## Rails Persistence

For conversations that survive app restarts, add a migration:

```ruby
class AddResponseIdToMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :messages, :response_id, :string
  end
end
```

Then use normally:

```ruby
# Day 1
chat = Chat.create!(model_id: 'gpt-4o-mini', provider: :openai_responses)
chat.ask("My name is Alice.")

# Day 2 (after restart)
chat = Chat.find(1)
chat.ask("What's my name?")  # => "Alice"
```

## Built-in Tools

The Responses API provides built-in tools that don't require custom implementation.

### Web Search

```ruby
chat.with_params(tools: [{ type: 'web_search_preview' }])
chat.ask("Latest news about Ruby 3.4?")
```

### Code Interpreter

Execute Python code in a sandbox:

```ruby
chat.with_params(tools: [{ type: 'code_interpreter' }])
chat.ask("Calculate the first 20 Fibonacci numbers and plot them")
```

### File Search

Search through uploaded files (requires vector store setup):

```ruby
chat.with_params(tools: [{ type: 'file_search', vector_store_ids: ['vs_abc123'] }])
chat.ask("What does the documentation say about authentication?")
```

### Combining Tools

```ruby
chat.with_params(tools: [
  { type: 'web_search_preview' },
  { type: 'code_interpreter' }
])
chat.ask("Find the latest Bitcoin price and plot a chart")
```

## Why Use the Responses API?

- **Built-in tools** - Web search, code execution, file search without custom implementation
- **Stateful conversations** - OpenAI stores context server-side via `previous_response_id`
- **Simpler multi-turn** - No need to send full message history on each request

## License

MIT
