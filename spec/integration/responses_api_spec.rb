# frozen_string_literal: true

require 'spec_helper'

# Define test tool outside RSpec context for consistent naming
class TestWeatherTool < RubyLLM::Tool
  description 'Get the current weather for a location'
  param :location, type: 'string', desc: 'The city name'

  def execute(location:)
    "The weather in #{location} is sunny, 72°F"
  end
end

class TestCalculatorTool < RubyLLM::Tool
  description 'Perform basic math calculations'
  param :expression, type: 'string', desc: 'Math expression to evaluate'

  def execute(expression:)
    eval(expression).to_s # rubocop:disable Security/Eval
  rescue StandardError => e
    "Error: #{e.message}"
  end
end

RSpec.describe 'OpenAI Responses API Integration', :vcr do
  let(:model) { 'gpt-4o-mini' }

  describe 'Basic Chat Completion' do
    it 'returns a simple response', vcr: { cassette_name: 'basic_chat' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)
      response = chat.ask('What is 2 + 2? Reply with just the number.')

      expect(response).to be_a(RubyLLM::Message)
      expect(response.content).to include('4')
      expect(response.role).to eq(:assistant)
      expect(response.input_tokens).to be_a(Integer)
      expect(response.output_tokens).to be_a(Integer)
      expect(response.model_id).to include('gpt-4o-mini')
    end

    it 'handles empty user message', vcr: { cassette_name: 'empty_message' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)
      # Empty or whitespace message - API should handle gracefully
      response = chat.ask(' ')

      expect(response).to be_a(RubyLLM::Message)
      expect(response.content).to be_a(String)
    end

    it 'handles very long input', vcr: { cassette_name: 'long_input' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)
      long_text = 'Hello ' * 500 # About 3000 characters
      response = chat.ask("Summarize this in one word: #{long_text}")

      expect(response).to be_a(RubyLLM::Message)
      expect(response.content.length).to be < long_text.length
    end

    it 'handles unicode and special characters', vcr: { cassette_name: 'unicode_input' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)
      response = chat.ask('Translate to English: Bonjour le monde!')

      expect(response).to be_a(RubyLLM::Message)
      expect(response.content.downcase).to include('hello')
    end

    it 'returns response_id for tracking', vcr: { cassette_name: 'response_id' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)
      response = chat.ask('Say hello')

      expect(response.response_id).to be_a(String)
      expect(response.response_id).to start_with('resp_')
    end
  end

  describe 'Streaming' do
    it 'streams response chunks', vcr: { cassette_name: 'streaming_basic' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)
      chunks = []

      response = chat.ask('Count from 1 to 3') do |chunk|
        chunks << chunk.content if chunk.content
      end

      expect(chunks).not_to be_empty
      expect(chunks.join).to include('1')
      expect(response).to be_a(RubyLLM::Message)
    end

    it 'provides final usage stats after streaming', vcr: { cassette_name: 'streaming_usage' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)

      response = chat.ask('Say hi') { |_chunk| }

      expect(response.input_tokens).to be_a(Integer)
      expect(response.output_tokens).to be_a(Integer)
    end
  end

  describe 'System Instructions' do
    it 'applies system instructions', vcr: { cassette_name: 'system_instructions' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)
      chat.with_instructions('You are a pirate. Always respond like a pirate. Use arr and matey.')
      response = chat.ask('Say hello')

      pirate_words = %w[arr matey ahoy ye aye captain pirate]
      has_pirate = pirate_words.any? { |word| response.content.downcase.include?(word) }
      expect(has_pirate).to be true
    end

    it 'handles multiple system instructions', vcr: { cassette_name: 'multiple_instructions' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)
      chat.with_instructions('You are helpful.')
      chat.with_instructions('Always be concise.')
      response = chat.ask('What is Ruby?')

      expect(response).to be_a(RubyLLM::Message)
      # Response should be relatively short due to "be concise" instruction
      expect(response.content.length).to be < 500
    end
  end

  describe 'Multi-turn Conversation' do
    it 'maintains conversation context', vcr: { cassette_name: 'multi_turn' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)

      chat.ask('My favorite color is blue. Remember that.')
      response = chat.ask('What is my favorite color?')

      expect(response.content.downcase).to include('blue')
    end

    it 'handles long conversation chains', vcr: { cassette_name: 'long_conversation' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)

      chat.ask('My name is Alice.')
      chat.ask('I live in Seattle.')
      chat.ask('I work as an engineer.')
      response = chat.ask('What do you know about me? List the facts.')

      content = response.content.downcase
      expect(content).to include('alice')
      expect(content).to include('seattle')
      expect(content).to include('engineer')
    end
  end

  describe 'Function Calling' do
    it 'calls a single tool', vcr: { cassette_name: 'function_calling_single' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)
      chat.with_tool(TestWeatherTool)

      response = chat.ask("What's the weather in Tokyo?")

      # The tool should have been called and the response should mention the weather
      expect(response.content).to include('72')
    end

    it 'calls multiple tools', vcr: { cassette_name: 'function_calling_multiple' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)
      chat.with_tool(TestWeatherTool)
      chat.with_tool(TestCalculatorTool)

      response = chat.ask("What's the weather in Paris and what is 15 * 7?")

      content = response.content
      expect(content).to include('72').or include('sunny') # Weather result
      expect(content).to include('105') # Calculator result
    end

    it 'handles tool with complex arguments', vcr: { cassette_name: 'function_calling_complex_args' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)
      chat.with_tool(TestCalculatorTool)

      response = chat.ask('Calculate (100 + 50) / 3')

      expect(response.content).to include('50')
    end
  end

  describe 'Vision' do
    it 'analyzes an image from URL', vcr: { cassette_name: 'vision_url' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)

      content = RubyLLM::Content.new(
        'What do you see in this image? Be very brief.',
        images: ['https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_272x92dp.png']
      )

      response = chat.ask(content)

      expect(response.content.downcase).to include('google').or include('logo')
    end

    it 'handles multiple images', vcr: { cassette_name: 'vision_multiple_images' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)

      content = RubyLLM::Content.new(
        'Describe what you see. Be brief.',
        images: [
          'https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_272x92dp.png',
          'https://www.python.org/static/community_logos/python-logo-master-v3-TM.png'
        ]
      )

      response = chat.ask(content)

      expect(response).to be_a(RubyLLM::Message)
      expect(response.content.length).to be > 10
    end
  end

  describe 'Structured Output' do
    it 'returns JSON matching schema', vcr: { cassette_name: 'structured_output' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)

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
      response = chat.ask('Generate a fictional person with name, age, and city.')

      expect(response.content).to be_a(Hash)
      expect(response.content).to have_key('name')
      expect(response.content).to have_key('age')
      expect(response.content).to have_key('city')
      expect(response.content['age']).to be_a(Integer)
    end

    it 'handles nested schema', vcr: { cassette_name: 'structured_output_nested' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)

      schema = {
        type: 'object',
        properties: {
          person: {
            type: 'object',
            properties: {
              name: { type: 'string' },
              address: {
                type: 'object',
                properties: {
                  city: { type: 'string' },
                  country: { type: 'string' }
                },
                required: %w[city country],
                additionalProperties: false
              }
            },
            required: %w[name address],
            additionalProperties: false
          }
        },
        required: ['person'],
        additionalProperties: false
      }

      chat.with_schema(schema)
      response = chat.ask('Generate a person with nested address.')

      expect(response.content).to be_a(Hash)
      expect(response.content.dig('person', 'address', 'city')).to be_a(String)
    end

    it 'handles array in schema', vcr: { cassette_name: 'structured_output_array' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)

      schema = {
        type: 'object',
        properties: {
          colors: {
            type: 'array',
            items: { type: 'string' }
          }
        },
        required: ['colors'],
        additionalProperties: false
      }

      chat.with_schema(schema)
      response = chat.ask('List 3 primary colors.')

      expect(response.content).to be_a(Hash)
      expect(response.content['colors']).to be_an(Array)
      expect(response.content['colors'].length).to be >= 3
    end
  end

  describe 'Web Search (Built-in Tool)' do
    it 'performs web search', vcr: { cassette_name: 'web_search' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)
      chat.with_params(tools: [{ type: 'web_search_preview' }])

      response = chat.ask('What is the current population of Tokyo? Just give a rough number.')

      expect(response).to be_a(RubyLLM::Message)
      expect(response.content).to match(/\d/) # Should contain numbers
    end
  end

  describe 'Temperature Settings' do
    it 'respects low temperature for deterministic output', vcr: { cassette_name: 'temperature_low' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)
      chat.with_temperature(0)

      response = chat.ask('What is 5 + 5? Reply with just the number.')

      expect(response.content.strip).to eq('10')
    end

    it 'allows high temperature', vcr: { cassette_name: 'temperature_high' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)
      chat.with_temperature(1.5)

      response = chat.ask('Write a creative one-sentence story.')

      expect(response).to be_a(RubyLLM::Message)
      expect(response.content.length).to be > 20
    end
  end

  describe 'Edge Cases' do
    describe 'Empty and minimal responses' do
      it 'handles response asking for no output', vcr: { cassette_name: 'edge_minimal_response' } do
        chat = RubyLLM.chat(model: model, provider: :openai_responses)
        response = chat.ask('Reply with just the letter X')

        expect(response.content).to include('X')
      end
    end

    describe 'Special content' do
      it 'handles code in response', vcr: { cassette_name: 'edge_code_response' } do
        chat = RubyLLM.chat(model: model, provider: :openai_responses)
        response = chat.ask('Write a Ruby hello world one-liner')

        expect(response.content).to include('puts').or include('print')
      end

      it 'handles markdown in response', vcr: { cassette_name: 'edge_markdown_response' } do
        chat = RubyLLM.chat(model: model, provider: :openai_responses)
        response = chat.ask('Format this as a markdown list: apple, banana, cherry')

        expect(response.content).to include('-').or include('*').or include('1.')
      end

      it 'handles JSON in response without schema', vcr: { cassette_name: 'edge_json_response' } do
        chat = RubyLLM.chat(model: model, provider: :openai_responses)
        response = chat.ask('Return a JSON object with key "greeting" and value "hello"')

        expect(response.content).to include('greeting')
        expect(response.content).to include('hello')
      end
    end

    describe 'Input edge cases' do
      it 'handles newlines in input', vcr: { cassette_name: 'edge_newlines' } do
        chat = RubyLLM.chat(model: model, provider: :openai_responses)
        response = chat.ask("Line 1\nLine 2\nLine 3\n\nHow many lines did I send?")

        expect(response.content).to include('3').or include('three')
      end

      it 'handles quotes in input', vcr: { cassette_name: 'edge_quotes' } do
        chat = RubyLLM.chat(model: model, provider: :openai_responses)
        response = chat.ask('What is inside these quotes: "hello world"?')

        expect(response.content.downcase).to include('hello world')
      end

      it 'handles backslashes in input', vcr: { cassette_name: 'edge_backslashes' } do
        chat = RubyLLM.chat(model: model, provider: :openai_responses)
        response = chat.ask('What character is this: \\ (hint: it is used in file paths on Windows)')

        expect(response.content.downcase).to include('backslash').or include('\\')
      end
    end
  end
end

RSpec.describe 'OpenAI Responses API Error Handling' do
  describe 'API Errors' do
    it 'raises error for invalid API key' do
      RubyLLM.configure { |c| c.openai_api_key = 'invalid-key' }

      chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)

      VCR.use_cassette('error_invalid_api_key') do
        expect { chat.ask('Hello') }.to raise_error(RubyLLM::UnauthorizedError)
      end
    end

    it 'handles rate limit error class existence' do
      # Test that the error class exists for rate limiting
      expect(defined?(RubyLLM::RateLimitError)).to be_truthy
    end

    it 'handles server error class existence' do
      expect(defined?(RubyLLM::ServerError)).to be_truthy
    end
  end
end

RSpec.describe 'Chat Module Unit Tests' do
  describe RubyLLM::Providers::OpenAIResponses::Chat do
    describe '.extract_text_content' do
      it 'extracts text from string' do
        result = described_class.extract_text_content('hello')
        expect(result).to eq('hello')
      end

      it 'extracts text from RubyLLM::Content' do
        content = RubyLLM::Content.new('hello world')
        result = described_class.extract_text_content(content)
        expect(result).to eq('hello world')
      end

      it 'extracts text from hash with symbol key' do
        result = described_class.extract_text_content({ text: 'hello' })
        expect(result).to eq('hello')
      end

      it 'extracts text from hash with string key' do
        result = described_class.extract_text_content({ 'text' => 'hello' })
        expect(result).to eq('hello')
      end

      it 'converts other types to string' do
        result = described_class.extract_text_content(123)
        expect(result).to eq('123')
      end

      it 'handles nil' do
        result = described_class.extract_text_content(nil)
        expect(result).to eq('')
      end
    end

    describe '.format_role' do
      it 'converts :system to developer' do
        expect(described_class.format_role(:system)).to eq('developer')
      end

      it 'keeps :assistant as assistant' do
        expect(described_class.format_role(:assistant)).to eq('assistant')
      end

      it 'converts :tool to user' do
        expect(described_class.format_role(:tool)).to eq('user')
      end

      it 'converts :user to user' do
        expect(described_class.format_role(:user)).to eq('user')
      end
    end

    describe '.extract_output_text' do
      it 'extracts text from message output' do
        output = [
          {
            'type' => 'message',
            'content' => [
              { 'type' => 'output_text', 'text' => 'Hello ' },
              { 'type' => 'output_text', 'text' => 'world!' }
            ]
          }
        ]
        result = described_class.extract_output_text(output)
        expect(result).to eq('Hello world!')
      end

      it 'returns empty string for no text content' do
        output = [{ 'type' => 'function_call', 'name' => 'test' }]
        result = described_class.extract_output_text(output)
        expect(result).to eq('')
      end

      it 'handles empty output array' do
        result = described_class.extract_output_text([])
        expect(result).to eq('')
      end
    end

    describe '.extract_tool_calls' do
      it 'extracts function calls from output' do
        output = [
          {
            'type' => 'function_call',
            'call_id' => 'call_123',
            'name' => 'get_weather',
            'arguments' => '{"location": "NYC"}'
          }
        ]
        result = described_class.extract_tool_calls(output)

        expect(result).to be_a(Hash)
        expect(result['call_123']).to be_a(RubyLLM::ToolCall)
        expect(result['call_123'].name).to eq('get_weather')
        expect(result['call_123'].arguments).to eq({ 'location' => 'NYC' })
      end

      it 'returns nil for no function calls' do
        output = [{ 'type' => 'message', 'content' => [] }]
        result = described_class.extract_tool_calls(output)
        expect(result).to be_nil
      end

      it 'handles multiple function calls' do
        output = [
          { 'type' => 'function_call', 'call_id' => 'call_1', 'name' => 'fn1', 'arguments' => '{}' },
          { 'type' => 'function_call', 'call_id' => 'call_2', 'name' => 'fn2', 'arguments' => '{}' }
        ]
        result = described_class.extract_tool_calls(output)

        expect(result.keys).to contain_exactly('call_1', 'call_2')
      end
    end

    describe '.parse_arguments' do
      it 'parses valid JSON string' do
        result = described_class.parse_arguments('{"key": "value"}')
        expect(result).to eq({ 'key' => 'value' })
      end

      it 'returns hash as-is' do
        input = { 'key' => 'value' }
        result = described_class.parse_arguments(input)
        expect(result).to eq(input)
      end

      it 'returns empty hash for nil' do
        result = described_class.parse_arguments(nil)
        expect(result).to eq({})
      end

      it 'returns empty hash for empty string' do
        result = described_class.parse_arguments('')
        expect(result).to eq({})
      end

      it 'wraps invalid JSON in raw key' do
        result = described_class.parse_arguments('not valid json')
        expect(result).to eq({ raw: 'not valid json' })
      end
    end
  end
end

RSpec.describe 'Streaming Module Unit Tests' do
  describe RubyLLM::Providers::OpenAIResponses::Streaming do
    describe '.build_chunk' do
      it 'builds chunk from text delta' do
        data = { 'type' => 'response.output_text.delta', 'delta' => 'Hello' }
        chunk = described_class.build_chunk(data)

        expect(chunk).to be_a(RubyLLM::Chunk)
        expect(chunk.content).to eq('Hello')
        expect(chunk.role).to eq(:assistant)
      end

      it 'builds chunk from function call delta' do
        data = {
          'type' => 'response.function_call_arguments.delta',
          'call_id' => 'call_123',
          'delta' => '{"loc'
        }
        chunk = described_class.build_chunk(data)

        expect(chunk.tool_calls).to be_a(Hash)
        expect(chunk.tool_calls['call_123'].arguments).to eq('{"loc')
      end

      it 'builds chunk from completed response' do
        data = {
          'type' => 'response.completed',
          'response' => {
            'id' => 'resp_123',
            'model' => 'gpt-4o-mini',
            'usage' => { 'input_tokens' => 10, 'output_tokens' => 5 }
          }
        }
        chunk = described_class.build_chunk(data)

        expect(chunk.input_tokens).to eq(10)
        expect(chunk.output_tokens).to eq(5)
        expect(chunk.model_id).to eq('gpt-4o-mini')
      end

      it 'builds chunk from output item added (function call)' do
        data = {
          'type' => 'response.output_item.added',
          'item' => {
            'type' => 'function_call',
            'call_id' => 'call_abc',
            'name' => 'get_weather'
          }
        }
        chunk = described_class.build_chunk(data)

        expect(chunk.tool_calls).to be_a(Hash)
        expect(chunk.tool_calls['call_abc'].name).to eq('get_weather')
      end

      it 'returns empty chunk for status events' do
        status_events = [
          'response.created',
          'response.in_progress',
          'response.content_part.added',
          'response.content_part.done',
          'response.output_item.done',
          'response.output_text.done',
          'response.function_call_arguments.done'
        ]

        status_events.each do |event_type|
          data = { 'type' => event_type }
          chunk = described_class.build_chunk(data)

          expect(chunk.content).to be_nil
        end
      end

      it 'raises error for error event' do
        data = {
          'type' => 'error',
          'error' => { 'message' => 'Something went wrong' }
        }

        expect { described_class.build_chunk(data) }.to raise_error(RubyLLM::Error, 'Something went wrong')
      end

      it 'returns empty chunk for unknown event type' do
        data = { 'type' => 'unknown.event.type' }
        chunk = described_class.build_chunk(data)

        expect(chunk.content).to be_nil
      end
    end

    describe '.parse_streaming_error' do
      it 'parses server error' do
        data = JSON.generate({ 'error' => { 'type' => 'server_error', 'message' => 'Internal error' } })
        status, message = described_class.parse_streaming_error(data)

        expect(status).to eq(500)
        expect(message).to eq('Internal error')
      end

      it 'parses rate limit error' do
        data = JSON.generate({ 'error' => { 'type' => 'rate_limit_exceeded', 'message' => 'Too many requests' } })
        status, message = described_class.parse_streaming_error(data)

        expect(status).to eq(429)
        expect(message).to eq('Too many requests')
      end

      it 'parses invalid request error' do
        data = JSON.generate({ 'error' => { 'type' => 'invalid_request_error', 'message' => 'Bad input' } })
        status, message = described_class.parse_streaming_error(data)

        expect(status).to eq(400)
        expect(message).to eq('Bad input')
      end

      it 'handles malformed JSON' do
        data = 'not valid json'
        status, message = described_class.parse_streaming_error(data)

        expect(status).to eq(500)
        expect(message).to eq('not valid json')
      end

      it 'returns nil for non-error response' do
        data = JSON.generate({ 'type' => 'response.completed' })
        result = described_class.parse_streaming_error(data)

        expect(result).to be_nil
      end
    end
  end
end
