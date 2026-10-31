# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::OpenAIResponses do
  include ResponseHelpers

  let(:config) do
    RubyLLM::Configuration.new.tap do |c|
      c.openai_api_key = 'test-api-key'
    end
  end
  let(:instrumenter) do
    Class.new do
      attr_reader :events

      def initialize
        @events = []
      end

      def instrument(name, payload)
        result = yield if block_given?
        @events << [name, payload.dup]
        result
      end
    end.new
  end

  let(:provider) { described_class.new(config) }

  describe '.configuration_requirements' do
    it 'requires openai_api_key' do
      expect(described_class.configuration_requirements).to eq(%i[openai_api_key])
    end
  end

  describe '.configuration_options' do
    it 'declares OpenAI configuration options used by the provider' do
      expect(described_class.configuration_options).to include(
        :openai_api_key,
        :openai_api_base,
        :openai_organization_id,
        :openai_project_id
      )
    end
  end

  describe '.slug' do
    it 'returns "openai_responses"' do
      expect(described_class.slug).to eq('openai_responses')
    end
  end

  describe '#api_base' do
    it 'returns the default OpenAI API base' do
      expect(provider.api_base).to eq('https://api.openai.com/v1')
    end

    it 'uses custom api_base from config' do
      config.openai_api_base = 'https://custom.api.com/v1'
      expect(provider.api_base).to eq('https://custom.api.com/v1')
    end
  end

  describe '#headers' do
    it 'includes Authorization header' do
      expect(provider.headers['Authorization']).to eq('Bearer test-api-key')
    end

    it 'includes organization header when set' do
      config.openai_organization_id = 'org-123'
      expect(provider.headers['OpenAI-Organization']).to eq('org-123')
    end

    it 'excludes nil headers' do
      expect(provider.headers).not_to have_key('OpenAI-Organization')
    end
  end

  describe '#compact_response' do
    it 'posts to the Responses compaction endpoint' do
      response = mock_response({ 'object' => 'response.compaction', 'output' => [] })
      allow(provider.connection).to receive(:post).and_return(response)

      result = provider.compact_response(
        model: 'gpt-5.5',
        input: [{ type: 'message', role: 'user', content: 'Hello' }],
        store: false
      )

      expect(provider.connection).to have_received(:post).with(
        'responses/compact',
        {
          model: 'gpt-5.5',
          input: [{ type: 'message', role: 'user', content: 'Hello' }],
          store: false
        }
      )
      expect(result['object']).to eq('response.compaction')
    end
  end

  describe '#count_input_tokens' do
    it 'posts to the Responses input token endpoint' do
      response = mock_response({ 'object' => 'response.tokens.input', 'input_tokens' => 11 })
      allow(provider.connection).to receive(:post).and_return(response)

      result = provider.count_input_tokens(model: 'gpt-5.5', input: 'Tell me a joke.', instructions: 'Be brief.')

      expect(provider.connection).to have_received(:post).with(
        'responses/input_tokens',
        {
          model: 'gpt-5.5',
          input: 'Tell me a joke.',
          instructions: 'Be brief.'
        }
      )
      expect(result['input_tokens']).to eq(11)
    end
  end
  describe 'native lifecycle transport' do
    it 'authenticates and instruments deletes without bypassing native error handling' do
      config.instrumenter = instrumenter
      stub_request(:delete, 'https://api.openai.com/v1/responses/resp_123')
        .with(headers: { 'Authorization' => 'Bearer test-api-key' })
        .to_return(status: 200, body: '{"deleted":true}', headers: { 'Content-Type' => 'application/json' })
      expect(provider.delete_response('resp_123')).to eq('deleted' => true)
      expect(instrumenter.events).to include(
        ['request.ruby_llm', hash_including(provider: 'openai_responses', method: :delete, status: 200)]
      )
    end

    it 'polls stored background responses and uses the native error classes' do
      stub_request(:get, 'https://api.openai.com/v1/responses/resp_123').to_return(
        { status: 200, body: '{"status":"in_progress"}', headers: { 'Content-Type' => 'application/json' } },
        { status: 200, body: '{"status":"completed"}', headers: { 'Content-Type' => 'application/json' } }
      )
      expect(provider.poll_response('resp_123', interval: 0)).to eq('status' => 'completed')
      stub_request(:delete, 'https://api.openai.com/v1/responses/resp_123')
        .to_return(status: 401, body: '{"error":{"message":"Not found"}}',
                   headers: { 'Content-Type' => 'application/json' })
      expect { provider.delete_response('resp_123') }.to raise_error(RubyLLM::UnauthorizedError)
    end
  end
end
