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

  describe '#complete with transport: :websocket' do
    let(:mock_ws) { instance_double(RubyLLM::Providers::OpenAIResponses::WebSocket) }
    let(:model) { double('Model', id: 'gpt-4o') }
    let(:messages) { [RubyLLM::Message.new(role: :user, content: 'Hello')] }
    let(:response_message) { RubyLLM::Message.new(role: :assistant, content: 'Hi there', response_id: 'resp_123') }

    before do
      allow(RubyLLM::Providers::OpenAIResponses::WebSocket).to receive(:new).and_return(mock_ws)
      allow(mock_ws).to receive(:connected?).and_return(false, true)
      allow(mock_ws).to receive(:connect).and_return(mock_ws)
      allow(mock_ws).to receive(:call).and_return(response_message)
    end

    it 'routes through WebSocket when transport: :websocket' do
      result = provider.complete(
        messages,
        tools: {},
        temperature: nil,
        model: model,
        params: { transport: :websocket }
      )

      expect(mock_ws).to have_received(:connect)
      expect(mock_ws).to have_received(:call)
      expect(result.content).to eq('Hi there')
    end

    it 'does not pass transport key to the WebSocket payload' do
      provider.complete(
        messages,
        tools: {},
        temperature: nil,
        model: model,
        params: { transport: :websocket }
      )

      expect(mock_ws).to have_received(:call) do |payload|
        expect(payload).not_to have_key(:transport)
      end
    end

    it 'falls through to HTTP when transport is not websocket' do
      allow(provider).to receive(:sync_response).and_return(response_message)

      provider.complete(
        messages,
        tools: {},
        temperature: nil,
        model: model,
        params: {}
      )

      expect(mock_ws).not_to have_received(:call)
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
      response = mock_response({ 'object' => 'response.input_tokens', 'input_tokens' => 11 })
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

  describe '#delete_response' do
    it 'instruments manual DELETE requests' do
      config.instrumenter = instrumenter
      response = mock_response({ 'deleted' => true }, status: 200)

      allow(provider.connection.connection).to receive(:delete).and_return(response)

      result = provider.delete_response('resp_123')

      expect(result).to eq({ 'deleted' => true })
      expect(provider.connection.connection).to have_received(:delete).with('responses/resp_123')
      expect(instrumenter.events).to include(
        [
          'request.ruby_llm',
          {
            provider: 'openai_responses',
            method: :delete,
            url: 'responses/resp_123',
            status: 200
          }
        ]
      )
    end

    it 'works without RubyLLM instrumentation support' do
      response = mock_response({ 'deleted' => true }, status: 200)

      allow(provider.connection.connection).to receive(:delete).and_return(response)
      allow(RubyLLM).to receive(:respond_to?).with(:instrument).and_return(false)

      result = provider.delete_response('resp_123')

      expect(result).to eq({ 'deleted' => true })
      expect(provider.connection.connection).to have_received(:delete).with('responses/resp_123')
    end
  end
end
