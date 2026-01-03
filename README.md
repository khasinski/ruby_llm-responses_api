# RubyLLM Responses API Provider

[![Gem Version](https://badge.fury.io/rb/ruby_llm-responses_api.svg)](https://badge.fury.io/rb/ruby_llm-responses_api)

A [RubyLLM](https://github.com/crmne/ruby_llm) provider plugin that implements OpenAI's [Responses API](https://platform.openai.com/docs/api-reference/responses). Get all the RubyLLM features you love, plus Responses API exclusives:

- **Built-in Tools**: Web search, code interpreter, file search, image generation
- **Stateful Conversations**: Server-side conversation memory with `previous_response_id`
- **Background Mode**: Submit long-running tasks and poll for results
- **MCP Integration**: Connect to Model Context Protocol servers

## Quick Start

```ruby
require 'ruby_llm-responses_api'

RubyLLM.configure do |config|
  config.openai_api_key = ENV['OPENAI_API_KEY']
end

# That's it! Use :openai_responses as your provider
chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)
response = chat.ask("What is 2 + 2?")
puts response.content  # => "4"
```

## Installation

Add to your Gemfile:

```ruby
gem 'ruby_llm-responses_api'
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install ruby_llm-responses_api
```

## Requirements

- Ruby >= 3.1.0
- [RubyLLM](https://github.com/crmne/ruby_llm) >= 1.0

## Features

### Basic Chat

```ruby
chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses)
response = chat.ask("Explain quantum computing in simple terms")
puts response.content
puts "Tokens used: #{response.input_tokens} in, #{response.output_tokens} out"
```

### Streaming

```ruby
chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)
chat.ask("Write a haiku about Ruby") do |chunk|
  print chunk.content
end
```

### System Instructions

```ruby
chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)
chat.with_instructions("You are a pirate. Always respond like a pirate.")
response = chat.ask("Hello!")
puts response.content  # "Ahoy, matey! What brings ye to these waters?"
```

### Function Calling (Tools)

```ruby
class GetWeatherTool < RubyLLM::Tool
  description "Get the current weather for a location"
  param :location, type: "string", desc: "The city name"

  def execute(location:)
    "The weather in #{location} is sunny, 72°F"
  end
end

chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)
chat.with_tool(GetWeatherTool)
response = chat.ask("What's the weather in Tokyo?")
puts response.content  # Uses the tool and returns weather info
```

### Multi-turn Conversations

```ruby
chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)
chat.ask("My favorite color is blue.")
response = chat.ask("What's my favorite color?")
puts response.content  # "Your favorite color is blue."
```

### Vision (Images)

```ruby
chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)

# From URL
content = RubyLLM::Content.new(
  "What do you see in this image?",
  images: ["https://example.com/image.png"]
)
response = chat.ask(content)

# From local file
content = RubyLLM::Content.new(
  "Describe this photo",
  images: ["/path/to/photo.jpg"]
)
response = chat.ask(content)
```

### Structured Output (JSON Schema)

```ruby
chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)

schema = {
  type: 'object',
  properties: {
    name: { type: 'string' },
    age: { type: 'integer' },
    city: { type: 'string' }
  },
  required: %w[name age city],
  additionalProperties: false
}

chat.with_schema(schema)
response = chat.ask("Generate a fictional person")
puts response.content  # => {"name"=>"Alice", "age"=>28, "city"=>"Seattle"}
```

## Responses API Exclusive Features

### Web Search

Enable real-time web search in responses:

```ruby
chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)
chat.with_params(tools: [{ type: 'web_search_preview' }])

response = chat.ask("What's the current Bitcoin price?")
puts response.content  # Real-time data from the web
```

Or use the helper:

```ruby
chat.with_params(tools: [RubyLLM::ResponsesAPI::BuiltInTools.web_search])
```

### Code Interpreter

Let the model execute Python code:

```ruby
chat = RubyLLM.chat(model: 'gpt-4.1', provider: :openai_responses)
chat.with_params(tools: [RubyLLM::ResponsesAPI::BuiltInTools.code_interpreter])

response = chat.ask("Calculate the first 20 fibonacci numbers and plot them")
```

### File Search (Vector Stores)

Search through your uploaded documents:

```ruby
chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses)
chat.with_params(
  tools: [
    RubyLLM::ResponsesAPI::BuiltInTools.file_search(
      vector_store_ids: ['vs_abc123']
    )
  ]
)

response = chat.ask("Find all mentions of authentication in the docs")
```

### Image Generation

Generate images directly in conversations:

```ruby
chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses)
chat.with_params(tools: [RubyLLM::ResponsesAPI::BuiltInTools.image_generation])

response = chat.ask("Generate an image of a sunset over mountains")
# Response will include generated image data
```

### Stateful Conversations (Server-side Memory)

Let OpenAI store conversation state:

```ruby
chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses)

# Store the conversation on OpenAI's servers
response = chat.ask("My name is Alice", params: { store: true })
response_id = response.response_id

# Later, continue from that conversation (even in a new session)
chat2 = RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses)
response = chat2.ask(
  "What's my name?",
  params: { previous_response_id: response_id }
)
puts response.content  # "Your name is Alice"
```

### Background Mode

For long-running tasks:

```ruby
provider = RubyLLM::Provider.resolve(:openai_responses).new(RubyLLM.config)

# Submit a background request
response = chat.ask(
  "Analyze this massive dataset",
  params: { background: true }
)

# Poll for completion
result = provider.poll_response(response.response_id, interval: 2.0) do |status|
  puts "Status: #{status['status']}"  # queued, in_progress, completed
end

puts result['output']
```

### MCP (Model Context Protocol)

Connect to external MCP servers:

```ruby
chat = RubyLLM.chat(model: 'gpt-4.1', provider: :openai_responses)

mcp_tool = RubyLLM::ResponsesAPI::BuiltInTools.mcp(
  server_label: 'github',
  server_url: 'https://mcp.example.com/github',
  require_approval: 'never',
  headers: { 'Authorization' => "Bearer #{ENV['GITHUB_TOKEN']}" }
)

chat.with_params(tools: [mcp_tool])
response = chat.ask("List my recent GitHub issues")
```

## Configuration

This gem reuses RubyLLM's OpenAI configuration:

```ruby
RubyLLM.configure do |config|
  # Required
  config.openai_api_key = ENV['OPENAI_API_KEY']

  # Optional
  config.openai_api_base = 'https://api.openai.com/v1'
  config.openai_organization_id = 'org-...'
  config.openai_project_id = 'proj-...'
end
```

## Supported Models

| Model Family | Models | Key Features |
|--------------|--------|--------------|
| GPT-4o | `gpt-4o`, `gpt-4o-mini` | Vision, function calling, web search |
| GPT-4.1 | `gpt-4.1`, `gpt-4.1-mini`, `gpt-4.1-nano` | 1M context, all features |
| O-series | `o1`, `o1-mini`, `o3`, `o3-mini`, `o4-mini` | Advanced reasoning |

## API Differences

The Responses API differs from Chat Completions:

| Feature | Chat Completions | Responses API |
|---------|-----------------|---------------|
| Endpoint | `/v1/chat/completions` | `/v1/responses` |
| System prompt | In messages array | `instructions` parameter |
| Response format | `choices[0].message` | `output` array |
| Statefulness | Client-managed | Server-managed via `previous_response_id` |
| Built-in tools | None | Web search, code interpreter, etc. |

## Development

```bash
git clone https://github.com/khasinski/ruby_llm-responses_api.git
cd ruby_llm-responses_api
bundle install
bundle exec rspec
```

Run integration tests with a real API:

```bash
OPENAI_API_KEY=your_key bundle exec ruby examples/test_real_api.rb
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/khasinski/ruby_llm-responses_api.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
