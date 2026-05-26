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

chat = RubyLLM.chat(model: 'gpt-5.5', provider: :openai_responses)
response = chat.ask("Hello!")
puts response.content
```

All standard RubyLLM features work as expected (streaming, tools, vision, structured output).

## Stateful Conversations

Conversations automatically chain via `previous_response_id`:

```ruby
chat = RubyLLM.chat(model: 'gpt-5.5', provider: :openai_responses)
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
chat = Chat.create!(model_id: 'gpt-5.5', provider: :openai_responses)
chat.ask("My name is Alice.")

# Day 2 (after restart)
chat = Chat.find(1)
chat.ask("What's my name?")  # => "Alice"
```

## Built-in Tools

The Responses API provides built-in tools that don't require custom implementation. Pass them as hashes via `with_params`, or use the `BuiltInTools` helper module.

### Web Search

```ruby
chat.with_params(tools: [{ type: 'web_search' }])
chat.ask("Latest news about Ruby 3.4?")

# Or with helper
tool = RubyLLM::ResponsesAPI::BuiltInTools.web_search(search_context_size: 'high')
chat.with_params(tools: [tool])

# Legacy preview type is still available when needed
tool = RubyLLM::ResponsesAPI::BuiltInTools.web_search_preview
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

### Shell

Execute commands in hosted containers or local terminal environments. Requires GPT-5 family models.

```ruby
# Auto-provisioned container (default)
chat = RubyLLM.chat(model: 'gpt-5.5', provider: :openai_responses)
chat.with_params(tools: [{ type: 'shell', environment: { type: 'container_auto' } }])
chat.ask("List all Python files in the project")

# Using helper
tool = RubyLLM::ResponsesAPI::BuiltInTools.shell
chat.with_params(tools: [tool])

# Reuse an existing container
tool = RubyLLM::ResponsesAPI::BuiltInTools.shell(container_id: 'cntr_abc123')

# With networking (allow specific domains)
tool = RubyLLM::ResponsesAPI::BuiltInTools.shell(
  network_policy: {
    type: 'allowlist',
    allowed_domains: ['pypi.org', 'github.com'],
    domain_secrets: [
      { domain: 'github.com', name: 'GITHUB_TOKEN', value: ENV['GITHUB_TOKEN'] }
    ]
  }
)

# With memory limit
tool = RubyLLM::ResponsesAPI::BuiltInTools.shell(memory_limit: '4g')

# Local execution (you handle running commands yourself)
tool = RubyLLM::ResponsesAPI::BuiltInTools.shell(environment_type: 'local')
```

### Apply Patch

Structured diff-based file editing. Requires GPT-5 family models.

```ruby
chat = RubyLLM.chat(model: 'gpt-5.5', provider: :openai_responses)
chat.with_params(tools: [{ type: 'apply_patch' }])
chat.ask("Add error handling to the User#save method")

# Using helper
tool = RubyLLM::ResponsesAPI::BuiltInTools.apply_patch
chat.with_params(tools: [tool])
```

### Image Generation

```ruby
chat.with_params(tools: [{ type: 'image_generation' }])
chat.ask("Generate an image of a sunset over mountains")
```

### MCP (Model Context Protocol)

```ruby
tool = RubyLLM::ResponsesAPI::BuiltInTools.mcp(
  server_label: 'github',
  server_url: 'https://api.github.com/mcp',
  require_approval: 'never'
)
chat.with_params(tools: [tool])
```

### Combining Tools

```ruby
chat.with_params(tools: [
  { type: 'web_search' },
  { type: 'code_interpreter' },
  { type: 'shell', environment: { type: 'container_auto' } }
])
chat.ask("Research the latest sorting algorithms and benchmark them")
```

## Server-Side Compaction

For multi-hour agent runs, enable server-side compaction to automatically compress conversation context when it exceeds a token threshold:

```ruby
chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses)

# Pass directly
chat.with_params(
  context_management: [{ type: 'compaction', compact_threshold: 200_000 }]
)

# Or use the helper
chat.with_params(
  **RubyLLM::ResponsesAPI::Compaction.compaction_params(compact_threshold: 150_000)
)

# Now run a long agent loop without worrying about context limits
loop do
  response = chat.ask(next_prompt)
  break if done?(response)
end
```

When the token count crosses the threshold, the server automatically compacts the conversation. The compacted state is carried forward transparently via `previous_response_id`.

You can also run an explicit compaction pass or count request input tokens before creating a response:

```ruby
provider = chat.instance_variable_get(:@provider)

compacted = provider.compact_response(
  model: 'gpt-5.5',
  input: [{ type: 'message', role: 'user', content: 'Summarize this long session...' }]
)

tokens = provider.count_input_tokens(
  model: 'gpt-5.5',
  input: 'Tell me a joke.'
)
puts tokens['input_tokens']
```

## Containers API

Manage persistent execution environments for the shell tool and code interpreter:

```ruby
chat = RubyLLM.chat(model: 'gpt-5.5', provider: :openai_responses)
provider = chat.instance_variable_get(:@provider)

# Create a container
container = provider.create_container(
  name: 'my-analysis-env',
  expires_after: { anchor: 'last_active_at', minutes: 60 },
  memory_limit: '4g'
)

# Use it with the shell tool
tool = RubyLLM::ResponsesAPI::BuiltInTools.shell(container_id: container['id'])
chat.with_params(tools: [tool])
chat.ask("Install pandas and run my analysis script")

# List files created in the container
files = provider.list_container_files(container['id'])

# Retrieve a specific file
content = provider.retrieve_container_file_content(container['id'], file_id)

# Clean up
provider.delete_container(container['id'])
```

## Background Mode

For long-running tasks:

```ruby
chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses)
chat.with_params(background: true)
response = chat.ask("Analyze this large dataset...")

# Poll for completion
provider = chat.instance_variable_get(:@provider)
result = provider.poll_response(response.response_id, interval: 2.0) do |status|
  puts "Status: #{status['status']}"
end
```

## Observing Built-in Tool Activity

Server-side built-in tools (web search, code interpreter, file search, shell, apply patch, image generation, MCP, computer use, local shell) fire through the same `on_tool_call` / `on_tool_result` callbacks as locally executed function tools:

```ruby
chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses)
chat.with_params(tools: [{ type: 'web_search' }])

chat.on_tool_call  { |tc| puts "#{tc.name} called (id=#{tc.id})" }
chat.on_tool_result { |r|  puts "  -> status=#{r[:status]}" }

chat.ask("What's the latest Ruby release?")
# web_search called (id=ws_...)
#   -> status=completed
```

The newer `before_tool_call` / `after_tool_result` API (ruby_llm 1.13+) is supported too. Each `ToolCall` carries a normalized name (`web_search`, `code_interpreter`, `file_search`, `image_generation`, `shell`, `apply_patch`, `mcp`, `computer`, `local_shell`) and best-effort arguments extracted from the response item.

## Parsing Built-in Tool Results

When you want the structured payload rather than just the callback, use the parsers:

```ruby
# Access raw response output (available via response.raw)
output = response.raw.body['output']

# Parse results by tool type
web_results    = RubyLLM::ResponsesAPI::BuiltInTools.parse_web_search_results(output)
code_results   = RubyLLM::ResponsesAPI::BuiltInTools.parse_code_interpreter_results(output)
file_results   = RubyLLM::ResponsesAPI::BuiltInTools.parse_file_search_results(output)
shell_results  = RubyLLM::ResponsesAPI::BuiltInTools.parse_shell_call_results(output)
patch_results  = RubyLLM::ResponsesAPI::BuiltInTools.parse_apply_patch_results(output)
image_results  = RubyLLM::ResponsesAPI::BuiltInTools.parse_image_generation_results(output)
citations      = RubyLLM::ResponsesAPI::BuiltInTools.extract_citations(message_content)
```

## Batch API

Process many requests asynchronously at 50% lower cost with a 24-hour completion window:

```ruby
# Create a batch
batch = RubyLLM.batch(model: 'gpt-4o', provider: :openai_responses)

# Add requests (auto-generates IDs or use your own)
batch.add("What is Ruby?")
batch.add("What is Python?", instructions: "Be brief", temperature: 0.5)
batch.add("Translate: hello", id: "translate_1")

# Submit (uploads JSONL file + creates batch)
batch.create!
batch.id  # => "batch_abc123"

# Poll until done
batch.wait!(interval: 60) { |b| puts "#{b.completed_count}/#{b.total_count}" }

# Get results as Messages keyed by custom_id
results = batch.results
results["request_0"].content  # => "Ruby is a dynamic..."
results["translate_1"].content  # => "Hola"

# Resume from a previous session
batch = RubyLLM.batch(id: "batch_abc123", provider: :openai_responses)
batch.results

# Cancel a running batch
batch.cancel!

# List existing batches
RubyLLM.batches(provider: :openai_responses)
```

**Constraints**: No `web_search`/`code_interpreter` tools, no `previous_response_id` chaining, max 50k requests per batch, 200MB file limit.

## WebSocket Mode

For agentic workflows with many tool-call round trips, WebSocket mode provides lower latency by maintaining a persistent connection instead of HTTP requests per turn.

Requires the `websocket-client-simple` gem:

```ruby
gem 'websocket-client-simple'
```

### Usage

Just add `transport: :websocket` to your params -- the standard `chat.ask` API works as-is:

```ruby
chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses)
chat.with_params(transport: :websocket)

chat.ask("Hello!")
chat.ask("What's 2+2?")  # reuses the same WebSocket connection
```

Streaming works the same way:

```ruby
chat.ask("Tell me a story") { |chunk| print chunk.content }
```

### Direct WebSocket access

For advanced use cases (raw Responses API format, warmup, explicit connection management):

```ruby
ws = RubyLLM::ResponsesAPI::WebSocket.new(api_key: ENV['OPENAI_API_KEY'])
ws.connect

ws.create_response(
  model: 'gpt-4o',
  input: [{ type: 'message', role: 'user', content: 'Hello!' }]
) { |chunk| print chunk.content }

# Pre-cache model weights
ws.warmup(model: 'gpt-4o')

ws.disconnect
```

## Why Use the Responses API?

- **Built-in tools** - Web search, code execution, file search, shell, apply patch without custom implementation
- **Stateful conversations** - OpenAI stores context server-side via `previous_response_id`
- **Simpler multi-turn** - No need to send full message history on each request
- **Server-side compaction** - Run multi-hour agent sessions without hitting context limits
- **Containers** - Persistent execution environments with networking and file management
- **WebSocket mode** - Lower-latency persistent connections for agentic tool-call loops
- **Batch API** - Process bulk requests at 50% lower cost with 24-hour turnaround

## License

MIT
