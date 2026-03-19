# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::OpenAIResponses::Streaming do
  describe '.build_chunk' do
    it 'builds chunk from text delta' do
      data = { 'type' => 'response.output_text.delta', 'delta' => 'Hello' }
      chunk = described_class.build_chunk(data)

      expect(chunk).to be_a(RubyLLM::Chunk)
      expect(chunk.content).to eq('Hello')
      expect(chunk.role).to eq(:assistant)
    end

    it 'builds chunk from function call delta without id (for accumulator append)' do
      data = {
        'type' => 'response.function_call_arguments.delta',
        'call_id' => 'call_123',
        'delta' => '{"loc'
      }
      chunk = described_class.build_chunk(data)

      expect(chunk.tool_calls).to be_a(Hash)
      tool_call = chunk.tool_calls['call_123']
      expect(tool_call.arguments).to eq('{"loc')
      expect(tool_call.id).to be_nil
      expect(tool_call.name).to be_nil
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

  describe 'tool call streaming accumulation' do
    # Simulates the real OpenAI Responses API event sequence for a tool call.
    # The output_item.added event carries the tool name; subsequent argument
    # delta events carry fragments that must be appended to the same entry.
    it 'accumulates tool call name and arguments from separate events' do
      accumulator = RubyLLM::StreamAccumulator.new

      # 1. output_item.added — establishes the tool call with name
      added = described_class.build_chunk(
        'type' => 'response.output_item.added',
        'item' => { 'type' => 'function_call', 'call_id' => 'call_abc', 'name' => 'get_weather' }
      )
      accumulator.add(added)

      # 2. function_call_arguments.delta — streams argument fragments
      ['{"city"', ':"Berlin"', '}'].each do |fragment|
        delta = described_class.build_chunk(
          'type' => 'response.function_call_arguments.delta',
          'call_id' => 'fc_xyz',
          'delta' => fragment
        )
        accumulator.add(delta)
      end

      # 3. response.completed — final usage stats
      completed = described_class.build_chunk(
        'type' => 'response.completed',
        'response' => { 'id' => 'resp_1', 'model' => 'gpt-4o',
                        'usage' => { 'input_tokens' => 10, 'output_tokens' => 5 } }
      )
      accumulator.add(completed)

      message = accumulator.to_message(nil)

      tool_calls = message.tool_calls
      expect(tool_calls).not_to be_empty

      # Find the entry with actual arguments
      tool_with_args = tool_calls.values.find { |tc| tc.arguments.is_a?(Hash) && tc.arguments.any? }
      expect(tool_with_args).not_to be_nil
      expect(tool_with_args.arguments).to eq({ 'city' => 'Berlin' })
    end

    it 'accumulates arguments when delta call_id matches added call_id' do
      accumulator = RubyLLM::StreamAccumulator.new

      added = described_class.build_chunk(
        'type' => 'response.output_item.added',
        'item' => { 'type' => 'function_call', 'call_id' => 'call_abc', 'name' => 'get_weather' }
      )
      accumulator.add(added)

      ['{"city"', ':"Berlin"', '}'].each do |fragment|
        delta = described_class.build_chunk(
          'type' => 'response.function_call_arguments.delta',
          'call_id' => 'call_abc',
          'delta' => fragment
        )
        accumulator.add(delta)
      end

      completed = described_class.build_chunk(
        'type' => 'response.completed',
        'response' => { 'id' => 'resp_1', 'model' => 'gpt-4o',
                        'usage' => { 'input_tokens' => 10, 'output_tokens' => 5 } }
      )
      accumulator.add(completed)

      message = accumulator.to_message(nil)
      tc = message.tool_calls['call_abc']

      expect(tc).not_to be_nil
      expect(tc.name).to eq('get_weather')
      expect(tc.arguments).to eq({ 'city' => 'Berlin' })
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

  describe '.stream_response' do
    let(:provider) { RubyLLM::Providers::OpenAIResponses.new(RubyLLM.config) }
    let(:payload) { { model: 'gpt-5.2', input: [], stream: true } }

    def build_stream_connection(events, response: mock_response('', status: 200))
      connection = instance_double(RubyLLM::Connection)

      allow(connection).to receive(:post) do |_url, _payload, &block|
        request = Struct.new(:headers, :options).new({}, Struct.new(:on_data).new)
        block.call(request)

        env = Struct.new(:status).new(200)
        sse_body = build_sse_body(events)
        request.options.on_data.call(sse_body, sse_body.bytesize, env)

        response
      end

      connection
    end

    it 'preserves completed shell executions on the final message raw output' do
      events = [
        { 'type' => 'response.output_text.delta', 'delta' => 'ruby 3.4.8' },
        {
          'type' => 'response.output_item.done',
          'item' => {
            'id' => 'sh_1',
            'type' => 'shell_call',
            'status' => 'completed',
            'action' => { 'commands' => ['placeholder'], 'timeout_ms' => nil },
            'call_id' => 'call_shell_1',
            'environment' => {
              'type' => 'container_reference',
              'container_id' => 'cntr_1'
            }
          },
          'output_index' => 0
        },
        {
          'type' => 'response.shell_call_command.done',
          'command' => 'cd /mnt/data/project && bundle exec ruby -v',
          'command_index' => 0,
          'output_index' => 0
        },
        {
          'type' => 'response.output_item.done',
          'item' => {
            'id' => 'sho_1',
            'type' => 'shell_call_output',
            'status' => 'completed',
            'call_id' => 'call_shell_1',
            'output' => []
          },
          'output_index' => 1
        },
        {
          'type' => 'response.shell_call_output_content.done',
          'command_index' => 0,
          'item_id' => 'sho_1',
          'output' => [
            {
              'outcome' => { 'type' => 'exit', 'exit_code' => 0 },
              'stderr' => '',
              'stdout' => "ruby 3.4.8\n"
            }
          ],
          'output_index' => 1
        },
        {
          'type' => 'response.output_item.done',
          'item' => {
            'id' => 'msg_1',
            'type' => 'message',
            'status' => 'completed',
            'role' => 'assistant',
            'content' => [
              {
                'type' => 'output_text',
                'text' => 'ruby 3.4.8'
              }
            ]
          },
          'output_index' => 2
        },
        {
          'type' => 'response.completed',
          'response' => {
            'id' => 'resp_shell',
            'model' => 'gpt-5.2',
            'output' => [
              {
                'id' => 'msg_1',
                'type' => 'message',
                'status' => 'completed',
                'role' => 'assistant',
                'content' => [
                  {
                    'type' => 'output_text',
                    'text' => 'ruby 3.4.8'
                  }
                ]
              }
            ],
            'usage' => { 'input_tokens' => 12, 'output_tokens' => 8 }
          }
        }
      ]

      message = provider.send(:stream_response, build_stream_connection(events), payload)
      results = RubyLLM::Providers::OpenAIResponses::BuiltInTools.parse_shell_call_results_from_message(message)

      expect(message.response_id).to eq('resp_shell')
      expect(message.raw.body['output'].map { |item| item['type'] }).to eq(
        %w[shell_call shell_call_output message]
      )
      expect(results).to eq(
        [
          {
            id: 'sh_1',
            call_id: 'call_shell_1',
            status: 'completed',
            environment: {
              'type' => 'container_reference',
              'container_id' => 'cntr_1'
            },
            action: {
              'commands' => ['cd /mnt/data/project && bundle exec ruby -v'],
              'timeout_ms' => nil
            },
            output: [
              {
                'outcome' => { 'type' => 'exit', 'exit_code' => 0 },
                'stderr' => '',
                'stdout' => "ruby 3.4.8\n"
              }
            ]
          }
        ]
      )
    end

    it 'handles multiple completed shell calls in one streamed response' do
      events = [
        {
          'type' => 'response.output_item.done',
          'item' => {
            'id' => 'sh_1',
            'type' => 'shell_call',
            'status' => 'completed',
            'action' => { 'commands' => ['echo one'] },
            'call_id' => 'call_shell_1',
            'environment' => { 'type' => 'container_reference', 'container_id' => 'cntr_1' }
          },
          'output_index' => 0
        },
        {
          'type' => 'response.output_item.done',
          'item' => {
            'id' => 'sho_1',
            'type' => 'shell_call_output',
            'status' => 'completed',
            'call_id' => 'call_shell_1',
            'output' => [
              {
                'outcome' => { 'type' => 'exit', 'exit_code' => 0 },
                'stderr' => '',
                'stdout' => "one\n"
              }
            ]
          },
          'output_index' => 1
        },
        {
          'type' => 'response.output_item.done',
          'item' => {
            'id' => 'sh_2',
            'type' => 'shell_call',
            'status' => 'completed',
            'action' => { 'commands' => ['echo two'] },
            'call_id' => 'call_shell_2',
            'environment' => { 'type' => 'container_reference', 'container_id' => 'cntr_2' }
          },
          'output_index' => 2
        },
        {
          'type' => 'response.output_item.done',
          'item' => {
            'id' => 'sho_2',
            'type' => 'shell_call_output',
            'status' => 'completed',
            'call_id' => 'call_shell_2',
            'output' => [
              {
                'outcome' => { 'type' => 'timeout' },
                'stderr' => 'timed out',
                'stdout' => ''
              }
            ]
          },
          'output_index' => 3
        },
        {
          'type' => 'response.completed',
          'response' => {
            'id' => 'resp_shell_multi',
            'model' => 'gpt-5.2',
            'output' => [],
            'usage' => { 'input_tokens' => 10, 'output_tokens' => 5 }
          }
        }
      ]

      message = provider.send(:stream_response, build_stream_connection(events), payload)
      results = RubyLLM::Providers::OpenAIResponses::BuiltInTools.parse_shell_call_results_from_message(message)

      expect(results.map { |result| result[:call_id] }).to eq(%w[call_shell_1 call_shell_2])
      expect(results.map { |result| result[:action]['commands'] }).to eq([['echo one'], ['echo two']])
      expect(results.last[:output]).to eq(
        [
          {
            'outcome' => { 'type' => 'timeout' },
            'stderr' => 'timed out',
            'stdout' => ''
          }
        ]
      )
    end

    it 'keeps function-call streaming reconstruction intact' do
      events = [
        {
          'type' => 'response.output_item.added',
          'item' => {
            'type' => 'function_call',
            'call_id' => 'call_fn_1',
            'name' => 'get_weather'
          }
        },
        {
          'type' => 'response.function_call_arguments.delta',
          'call_id' => 'call_fn_1',
          'delta' => '{"city":"'
        },
        {
          'type' => 'response.function_call_arguments.delta',
          'call_id' => 'call_fn_1',
          'delta' => 'Berlin"}'
        },
        {
          'type' => 'response.completed',
          'response' => {
            'id' => 'resp_fn_1',
            'model' => 'gpt-4o',
            'output' => [
              {
                'type' => 'function_call',
                'call_id' => 'call_fn_1',
                'name' => 'get_weather',
                'arguments' => '{"city":"Berlin"}'
              }
            ],
            'usage' => { 'input_tokens' => 6, 'output_tokens' => 4 }
          }
        }
      ]

      message = provider.send(:stream_response, build_stream_connection(events), payload)

      expect(message.tool_calls['call_fn_1'].name).to eq('get_weather')
      expect(message.tool_calls['call_fn_1'].arguments).to eq({ 'city' => 'Berlin' })
      expect(message.raw.body['output'].first['type']).to eq('function_call')
    end
  end
end
