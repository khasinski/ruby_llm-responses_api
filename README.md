# RubyLLM Responses API Provider

A RubyLLM provider that implements OpenAI's Responses API, providing access to built-in tools (web search, code interpreter, file search), stateful conversations, background mode, and MCP support.

## Requirements

- Ruby >= 3.1.0
- [RubyLLM](https://github.com/crmne/ruby_llm) >= 1.0

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rubyllm-responses-api'
```

And then execute:

```bash
bundle install
```

Or install it yourself:

```bash
gem install rubyllm-responses-api
```

## Usage

### Basic Usage

```ruby
require 'rubyllm_responses_api'

# Configure RubyLLM with your OpenAI API key
RubyLLM.configure do |config|
  config.openai_api_key = ENV['OPENAI_API_KEY']
end

# Use the Responses API provider
chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses)
response = chat.ask("What's the weather like today?")
puts response.content
```

### Streaming

```ruby
chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses)
chat.ask("Tell me a story") do |chunk|
  print chunk.content
end
```

### Using Built-in Tools

#### Web Search

```ruby
chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses)

# Add web search tool to the request
response = chat.ask(
  "What are the latest developments in Ruby?",
  params: {
    tools: [RubyLLM::ResponsesAPI::BuiltInTools.web_search]
  }
)
```

#### Code Interpreter

```ruby
chat = RubyLLM.chat(model: 'gpt-4.1', provider: :openai_responses)

response = chat.ask(
  "Calculate the fibonacci sequence up to 100",
  params: {
    tools: [RubyLLM::ResponsesAPI::BuiltInTools.code_interpreter]
  }
)
```

#### File Search (Vector Store)

```ruby
chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses)

response = chat.ask(
  "Find information about API authentication",
  params: {
    tools: [
      RubyLLM::ResponsesAPI::BuiltInTools.file_search(
        vector_store_ids: ['vs_abc123']
      )
    ]
  }
)
```

### Stateful Conversations

The Responses API supports server-side conversation state management:

```ruby
chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses)

# First message - stored on server
response = chat.ask(
  "My name is Alice",
  params: { store: true }
)
response_id = response.response_id

# Continue the conversation using the stored state
response2 = chat.ask(
  "What's my name?",
  params: { previous_response_id: response_id }
)
puts response2.content  # "Your name is Alice"
```

### Background Mode (Long-running tasks)

For tasks that take a long time, use background mode:

```ruby
provider = RubyLLM::Provider.resolve(:openai_responses).new(RubyLLM.config)

# Submit a background request
response = chat.ask(
  "Analyze this large dataset and generate a comprehensive report",
  params: { background: true }
)

# Poll for completion
final_response = provider.poll_response(response.response_id, interval: 2.0) do |status|
  puts "Status: #{status['status']}"
end

puts final_response['output']
```

### MCP (Model Context Protocol) Integration

Connect to remote MCP servers:

```ruby
chat = RubyLLM.chat(model: 'gpt-4.1', provider: :openai_responses)

response = chat.ask(
  "Analyze this GitHub repository",
  params: {
    tools: [
      RubyLLM::ResponsesAPI::BuiltInTools.mcp(
        server_label: 'github',
        server_url: 'https://mcp.example.com/github',
        require_approval: 'never',
        headers: { 'Authorization' => "Bearer #{ENV['GITHUB_TOKEN']}" }
      )
    ]
  }
)
```

### Function Calling

Standard function calling works the same as with the regular OpenAI provider:

```ruby
weather_tool = RubyLLM::Tool.new(
  name: 'get_weather',
  description: 'Get the current weather for a location',
  parameters: {
    location: { type: 'string', description: 'City name' }
  }
) do |args|
  "The weather in #{args[:location]} is sunny, 72°F"
end

chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses)
chat.with_tool(weather_tool)
response = chat.ask("What's the weather in San Francisco?")
```

## API Differences

The Responses API has some key differences from the Chat Completions API:

| Feature | Chat Completions | Responses API |
|---------|-----------------|---------------|
| Endpoint | `/v1/chat/completions` | `/v1/responses` |
| System prompt | In messages array | `instructions` parameter |
| Response format | `choices[0].message` | `output` array |
| Statefulness | None | `previous_response_id`, `store` |
| Built-in tools | None | web_search, file_search, code_interpreter |

## Configuration

This gem reuses RubyLLM's OpenAI configuration:

```ruby
RubyLLM.configure do |config|
  config.openai_api_key = ENV['OPENAI_API_KEY']
  config.openai_api_base = 'https://api.openai.com/v1'  # Optional
  config.openai_organization_id = 'org-...'  # Optional
  config.openai_project_id = 'proj-...'  # Optional
end
```

## Supported Models

The Responses API supports these model families:
- GPT-4o series (gpt-4o, gpt-4o-mini)
- GPT-4.1 series (gpt-4.1, gpt-4.1-mini, gpt-4.1-nano)
- O-series reasoning models (o1, o1-mini, o3, o3-mini, o4-mini)
- GPT-4 Turbo

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, run `bundle exec rspec` to run the tests.

```bash
git clone https://github.com/hasik/rubyllm-responses-api.git
cd rubyllm-responses-api
bundle install
bundle exec rspec
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/hasik/rubyllm-responses-api.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
