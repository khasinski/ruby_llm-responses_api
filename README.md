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

For conversations that survive app restarts:

**1. Add migration:**

```ruby
class AddResponseIdToMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :messages, :response_id, :string
  end
end
```

**2. Enable in initializer:**

```ruby
# config/initializers/ruby_llm.rb
RubyLLM::Providers::OpenAIResponses.apply_active_record_extensions!
```

**3. Use normally:**

```ruby
# Day 1
chat = Chat.create!(model_id: 'gpt-4o-mini', provider: :openai_responses)
chat.ask("My name is Alice.")

# Day 2 (after restart)
chat = Chat.find(1)
chat.ask("What's my name?")  # => "Alice"
```

## Web Search

```ruby
chat.with_params(tools: [{ type: 'web_search_preview' }])
chat.ask("Latest news about Ruby?")
```

## License

MIT
