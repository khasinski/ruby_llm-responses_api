# frozen_string_literal: true

require 'bundler/setup'
require 'rubyllm_responses_api'
require 'webmock/rspec'
require 'vcr'

# VCR Configuration
VCR.configure do |config|
  config.cassette_library_dir = 'spec/cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Filter sensitive data
  config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV.fetch('OPENAI_API_KEY', 'test-api-key') }
  config.filter_sensitive_data('<OPENAI_API_KEY>') do |interaction|
    auth_header = interaction.request.headers['Authorization']&.first
    auth_header&.sub('Bearer ', '')
  end

  # Allow real HTTP connections when recording
  config.allow_http_connections_when_no_cassette = false

  # Default cassette options
  config.default_cassette_options = {
    record: :once,
    match_requests_on: %i[method uri body],
    decode_compressed_response: true
  }

  # Ignore localhost for development
  config.ignore_localhost = true
end

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = true

  config.order = :random
  Kernel.srand config.seed

  # Configure RubyLLM before each test
  config.before(:each) do
    RubyLLM.configure do |c|
      c.openai_api_key = ENV.fetch('OPENAI_API_KEY', 'test-api-key')
    end
  end
end

# Helper to build mock responses
module ResponseHelpers
  def mock_response(body, status: 200)
    instance_double(
      Faraday::Response,
      body: body,
      status: status,
      success?: status < 400
    )
  end

  def sample_completion_response
    {
      'id' => 'resp_123',
      'object' => 'response',
      'model' => 'gpt-4o',
      'status' => 'completed',
      'output' => [
        {
          'type' => 'message',
          'role' => 'assistant',
          'content' => [
            {
              'type' => 'output_text',
              'text' => 'Hello! How can I help you today?'
            }
          ]
        }
      ],
      'usage' => {
        'input_tokens' => 10,
        'output_tokens' => 8
      }
    }
  end

  def sample_tool_call_response
    {
      'id' => 'resp_456',
      'object' => 'response',
      'model' => 'gpt-4o',
      'status' => 'completed',
      'output' => [
        {
          'type' => 'function_call',
          'call_id' => 'call_abc123',
          'name' => 'get_weather',
          'arguments' => '{"location": "San Francisco"}'
        }
      ],
      'usage' => {
        'input_tokens' => 15,
        'output_tokens' => 20
      }
    }
  end

  def sample_error_response(message: 'Invalid request', type: 'invalid_request_error', code: nil)
    {
      'error' => {
        'message' => message,
        'type' => type,
        'code' => code
      }
    }
  end

  def sample_streaming_events
    [
      { 'type' => 'response.created', 'response' => { 'id' => 'resp_123', 'status' => 'in_progress' } },
      { 'type' => 'response.in_progress', 'response' => { 'id' => 'resp_123' } },
      { 'type' => 'response.output_item.added', 'item' => { 'type' => 'message', 'role' => 'assistant' } },
      { 'type' => 'response.content_part.added', 'part' => { 'type' => 'output_text', 'text' => '' } },
      { 'type' => 'response.output_text.delta', 'delta' => 'Hello' },
      { 'type' => 'response.output_text.delta', 'delta' => ' world' },
      { 'type' => 'response.output_text.delta', 'delta' => '!' },
      { 'type' => 'response.output_text.done', 'text' => 'Hello world!' },
      { 'type' => 'response.content_part.done', 'part' => { 'type' => 'output_text', 'text' => 'Hello world!' } },
      { 'type' => 'response.output_item.done', 'item' => { 'type' => 'message' } },
      {
        'type' => 'response.completed',
        'response' => {
          'id' => 'resp_123',
          'model' => 'gpt-4o-mini',
          'status' => 'completed',
          'usage' => { 'input_tokens' => 10, 'output_tokens' => 3 }
        }
      }
    ]
  end

  def build_sse_body(events)
    events.map { |event| "data: #{JSON.generate(event)}\n\n" }.join
  end
end

RSpec.configure do |config|
  config.include ResponseHelpers
end
