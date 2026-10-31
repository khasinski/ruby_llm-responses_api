# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::OpenAIResponses::Batches do
  let(:batches) { RubyLLM::Providers::OpenAIResponses::Batches }

  describe 'URL helpers' do
    it 'returns files URL' do
      expect(batches.files_url).to eq('files')
    end

    it 'returns batches base URL' do
      expect(batches.batches_url).to eq('batches')
    end

    it 'returns batch URL with ID' do
      expect(batches.batch_url('batch_abc')).to eq('batches/batch_abc')
    end

    it 'returns cancel batch URL' do
      expect(batches.cancel_batch_url('batch_abc')).to eq('batches/batch_abc/cancel')
    end

    it 'returns file content URL' do
      expect(batches.file_content_url('file_123')).to eq('files/file_123/content')
    end
  end

  describe '.build_jsonl' do
    it 'builds JSONL from requests' do
      requests = [
        { custom_id: 'req_0', body: { model: 'gpt-4o', input: [{ type: 'message', role: 'user', content: 'Hello' }] } },
        { custom_id: 'req_1', body: { model: 'gpt-4o', input: [{ type: 'message', role: 'user', content: 'World' }] } }
      ]

      jsonl = batches.build_jsonl(requests)
      lines = jsonl.split("\n")

      expect(lines.length).to eq(2)

      first = JSON.parse(lines[0])
      expect(first['custom_id']).to eq('req_0')
      expect(first['method']).to eq('POST')
      expect(first['url']).to eq('/v1/responses')
      expect(first['body']['model']).to eq('gpt-4o')

      second = JSON.parse(lines[1])
      expect(second['custom_id']).to eq('req_1')
    end
  end

  describe '.normalize_input' do
    it 'wraps a string into Responses API input format' do
      result = batches.normalize_input('Hello')
      expect(result).to eq([{ type: 'message', role: 'user', content: 'Hello' }])
    end

    it 'passes arrays through unchanged' do
      input = [{ type: 'message', role: 'user', content: 'Hello' }]
      expect(batches.normalize_input(input)).to eq(input)
    end
  end

  describe 'status helpers' do
    it 'identifies terminal statuses' do
      expect(batches.terminal?('completed')).to be true
      expect(batches.terminal?('failed')).to be true
      expect(batches.terminal?('cancelled')).to be true
      expect(batches.terminal?('expired')).to be true
      expect(batches.terminal?('in_progress')).to be false
    end

    it 'identifies pending statuses' do
      expect(batches.pending?('validating')).to be true
      expect(batches.pending?('in_progress')).to be true
      expect(batches.pending?('cancelling')).to be true
      expect(batches.pending?('completed')).to be false
    end
  end

  describe '.parse_results' do
    it 'parses JSONL into array of hashes' do
      jsonl = [
        '{"custom_id":"req_0","response":{"status_code":200,"body":{"output":[]}}}',
        '{"custom_id":"req_1","response":{"status_code":200,"body":{"output":[]}}}'
      ].join("\n")

      results = batches.parse_results(jsonl)
      expect(results.length).to eq(2)
      expect(results[0]['custom_id']).to eq('req_0')
      expect(results[1]['custom_id']).to eq('req_1')
    end

    it 'skips blank lines' do
      jsonl = "{\"custom_id\":\"req_0\"}\n\n{\"custom_id\":\"req_1\"}\n"
      results = batches.parse_results(jsonl)
      expect(results.length).to eq(2)
    end
  end

  describe '.parse_results_to_messages' do
    it 'converts JSONL output to a hash of Messages' do
      jsonl = JSON.generate({
                              custom_id: 'req_0',
                              response: {
                                status_code: 200,
                                body: {
                                  model: 'gpt-4o',
                                  output: [
                                    {
                                      type: 'message',
                                      role: 'assistant',
                                      content: [{ type: 'output_text', text: 'Hello from batch!' }]
                                    }
                                  ],
                                  usage: { input_tokens: 10, output_tokens: 5 }
                                }
                              }
                            })

      messages = batches.parse_results_to_messages(jsonl)
      expect(messages).to be_a(Hash)
      expect(messages.keys).to eq(['req_0'])

      msg = messages['req_0']
      expect(msg).to be_a(RubyLLM::Message)
      expect(msg.role).to eq(:assistant)
      expect(msg.content).to eq('Hello from batch!')
      expect(msg.tokens.input).to eq(10)
      expect(msg.tokens.output).to eq(5)
    end

    it 'handles tool call results' do
      jsonl = JSON.generate({
                              custom_id: 'req_0',
                              response: {
                                status_code: 200,
                                body: {
                                  model: 'gpt-4o',
                                  output: [
                                    {
                                      type: 'function_call',
                                      call_id: 'call_abc',
                                      name: 'get_weather',
                                      arguments: '{"city":"NYC"}'
                                    }
                                  ],
                                  usage: { input_tokens: 10, output_tokens: 15 }
                                }
                              }
                            })

      messages = batches.parse_results_to_messages(jsonl)
      msg = messages['req_0']
      expect(msg.tool_calls).to be_a(Hash)
      expect(msg.tool_calls['call_abc'].name).to eq('get_weather')
    end
  end

  describe '.parse_errors' do
    it 'filters for error entries' do
      jsonl = [
        '{"custom_id":"req_0","response":{"status_code":200,"body":{"output":[]}}}',
        '{"custom_id":"req_1","response":{"status_code":400,"body":{"error":{"message":"Bad request"}}}}'
      ].join("\n")

      errors = batches.parse_errors(jsonl)
      expect(errors.length).to eq(1)
      expect(errors[0]['custom_id']).to eq('req_1')
    end
  end

  describe 'namespace access' do
    it 'is accessible via RubyLLM::ResponsesAPI::Batches' do
      expect(RubyLLM::ResponsesAPI::Batches).to eq(batches)
    end
  end
end
