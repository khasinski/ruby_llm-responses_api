# frozen_string_literal: true

require 'bundler/setup'
require 'rubyllm_responses_api'
require 'webmock/rspec'

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
end

RSpec.configure do |config|
  config.include ResponseHelpers
end
