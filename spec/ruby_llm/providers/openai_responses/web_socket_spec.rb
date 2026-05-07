# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::OpenAIResponses::WebSocket do
  let(:api_key) { 'test-api-key' }
  let(:mock_ws_client) { MockWSClient.new }
  let(:mock_client_class) { MockWSClientClass.new(mock_ws_client) }
  let(:ws) { described_class.new(api_key: api_key, client_class: mock_client_class) }

  WSMessage = Struct.new(:data) unless defined?(WSMessage)

  # Lightweight mock that captures on() handlers and send() calls,
  # avoiding any dependency on the real websocket-client-simple gem.
  class MockWSClient # rubocop:disable Lint/ConstantDefinitionInBlock
    attr_reader :sent_messages

    def initialize
      @handlers = Hash.new { |h, k| h[k] = [] }
      @sent_messages = []
    end

    def on(event, &block)
      @handlers[event] << block
    end

    def send(data)
      @sent_messages << data
    end

    def close; end

    def emit(event, *args)
      @handlers[event].each { |h| h.call(*args) }
    end

    def has_handler?(event)
      @handlers.key?(event)
    end
  end

  class MockWSClientClass # rubocop:disable Lint/ConstantDefinitionInBlock
    attr_reader :client

    def initialize(client)
      @client = client
    end

    def connect(_url, **_opts)
      @client
    end
  end

  # Helper: connect the ws instance by firing the :open event
  def connect_ws!
    thread = Thread.new do
      Thread.pass until mock_ws_client.has_handler?(:open)
      mock_ws_client.emit(:open)
    end
    ws.connect(timeout: 2)
    thread.join
  end

  # Helper: push WS events into the client's :message handlers
  def push_events(*events)
    events.each do |event|
      mock_ws_client.emit(:message, WSMessage.new(JSON.generate(event)))
    end
  end

  # Helper: fire events in a thread while the block executes
  def with_events(events, &block)
    thread = Thread.new do
      Thread.pass
      push_events(*events)
    end
    result = block.call
    thread.join
    result
  end

  def standard_events(text_deltas: ['OK'], response_id: 'resp_ws_test')
    events = [
      { 'type' => 'response.created', 'response' => { 'id' => response_id, 'status' => 'in_progress' } },
      { 'type' => 'response.in_progress', 'response' => { 'id' => response_id } },
      { 'type' => 'response.output_item.added', 'item' => { 'type' => 'message', 'role' => 'assistant' } },
      { 'type' => 'response.content_part.added', 'part' => { 'type' => 'output_text', 'text' => '' } }
    ]
    text_deltas.each { |d| events << { 'type' => 'response.output_text.delta', 'delta' => d } }
    events << {
      'type' => 'response.completed',
      'response' => { 'id' => response_id, 'model' => 'gpt-4o', 'status' => 'completed',
                      'usage' => { 'input_tokens' => 10, 'output_tokens' => 5 } }
    }
    events
  end

  def last_sent_payload
    JSON.parse(mock_ws_client.sent_messages.last)
  end

  # --- Specs ---

  describe '#initialize' do
    it 'stores configuration' do
      socket = described_class.new(
        api_key: 'sk-test',
        api_base: 'https://custom.api.com/v1',
        organization_id: 'org-123',
        project_id: 'proj-456'
      )

      expect(socket).not_to be_connected
      expect(socket.last_response_id).to be_nil
    end
  end

  describe '#connect' do
    it 'establishes a WebSocket connection' do
      connect_ws!
      expect(ws).to be_connected
    end

    it 'raises ConnectionError on timeout' do
      expect { ws.connect(timeout: 0.1) }.to raise_error(
        described_class::ConnectionError, /timeout/
      )
    end

    it 'raises ConnectionError on error event' do
      thread = Thread.new do
        Thread.pass until mock_ws_client.has_handler?(:error)
        mock_ws_client.emit(:error, StandardError.new('connection refused'))
      end

      expect { ws.connect(timeout: 2) }.to raise_error(
        described_class::ConnectionError, /connection refused/
      )
      thread.join
    end
  end

  describe '#create_response' do
    before { connect_ws! }

    it 'sends correct payload envelope' do
      with_events(standard_events) do
        ws.create_response(model: 'gpt-4o', input: [{ type: 'message', role: 'user', content: 'Hello' }])
      end

      payload = last_sent_payload
      expect(payload['type']).to eq('response.create')
      expect(payload['model']).to eq('gpt-4o')
      expect(payload['input']).to eq([{ 'type' => 'message', 'role' => 'user', 'content' => 'Hello' }])
    end

    it 'includes tools in payload when provided' do
      tools = [{ type: 'web_search_preview' }, { type: 'code_interpreter', container: { type: 'auto' } }]

      with_events(standard_events) do
        ws.create_response(model: 'gpt-4o', input: [], tools: tools)
      end

      expect(last_sent_payload['tools']).to be_an(Array)
      expect(last_sent_payload['tools'].length).to eq(2)
    end

    it 'routes events through Streaming.build_chunk and yields chunks' do
      chunks = []

      with_events(standard_events(text_deltas: ['Hello', ' world'])) do
        ws.create_response(model: 'gpt-4o', input: []) { |chunk| chunks << chunk }
      end

      text_chunks = chunks.select(&:content)
      expect(text_chunks.map(&:content)).to eq(['Hello', ' world'])
    end

    it 'returns assembled Message' do
      message = with_events(standard_events(text_deltas: %w[Hi there])) do
        ws.create_response(model: 'gpt-4o', input: [])
      end

      expect(message).to be_a(RubyLLM::Message)
      expect(message.role).to eq(:assistant)
      expect(message.content).to eq('Hithere')
    end

    it 'tracks last_response_id' do
      with_events(standard_events(response_id: 'resp_ws_001')) do
        ws.create_response(model: 'gpt-4o', input: [])
      end

      expect(ws.last_response_id).to eq('resp_ws_001')
    end

    it 'auto-chains with previous last_response_id' do
      with_events(standard_events(response_id: 'resp_ws_001')) do
        ws.create_response(model: 'gpt-4o', input: [{ type: 'message', role: 'user', content: 'First' }])
      end

      with_events(standard_events(response_id: 'resp_ws_002')) do
        ws.create_response(model: 'gpt-4o', input: [{ type: 'message', role: 'user', content: 'Second' }])
      end

      expect(last_sent_payload['previous_response_id']).to eq('resp_ws_001')
      expect(ws.last_response_id).to eq('resp_ws_002')
    end

    it 'allows explicit previous_response_id override' do
      with_events(standard_events) do
        ws.create_response(model: 'gpt-4o', input: [], previous_response_id: 'resp_explicit_123')
      end

      expect(last_sent_payload['previous_response_id']).to eq('resp_explicit_123')
    end

    it 'includes instructions when provided' do
      with_events(standard_events) do
        ws.create_response(model: 'gpt-4o', input: [], instructions: 'You are a helpful assistant.')
      end

      expect(last_sent_payload['instructions']).to eq('You are a helpful assistant.')
    end

    it 'raises on error event' do
      error_event = {
        'type' => 'error',
        'error' => { 'message' => 'Rate limit exceeded', 'type' => 'rate_limit_exceeded' }
      }

      expect do
        with_events([error_event]) do
          ws.create_response(model: 'gpt-4o', input: [])
        end
      end.to raise_error(RubyLLM::Error, /Rate limit exceeded/)
    end

    it 'rejects concurrent create_response calls' do
      ws.instance_variable_set(:@in_flight, true)

      expect do
        ws.create_response(model: 'gpt-4o', input: [])
      end.to raise_error(described_class::ConcurrencyError)
    end

    it 'applies state params (store, metadata)' do
      with_events(standard_events) do
        ws.create_response(model: 'gpt-4o', input: [], store: false, metadata: { session: 'abc' })
      end

      payload = last_sent_payload
      expect(payload['store']).to be false
      expect(payload['metadata']).to eq({ 'session' => 'abc' })
    end

    it 'applies compaction params' do
      with_events(standard_events) do
        ws.create_response(model: 'gpt-4o', input: [], compact_threshold: 100_000)
      end

      expect(last_sent_payload['context_management']).to eq(
        [{ 'type' => 'compaction', 'compact_threshold' => 100_000 }]
      )
    end

    it 'does not leak known params into the API payload' do
      with_events(standard_events) do
        ws.create_response(model: 'gpt-4o', input: [], store: true, compact_threshold: 50_000)
      end

      response_payload = last_sent_payload
      expect(response_payload).not_to have_key('compact_threshold')
    end

    it 'cleans up message_queue after response completes' do
      with_events(standard_events) do
        ws.create_response(model: 'gpt-4o', input: [])
      end

      expect(ws.instance_variable_get(:@message_queue)).to be_nil
    end
  end

  describe '#call' do
    before { connect_ws! }

    it 'accepts a pre-built payload and wraps in WS envelope' do
      payload = { model: 'gpt-4o', input: [{ type: 'message', role: 'user', content: 'Hi' }] }

      with_events(standard_events) do
        ws.call(payload)
      end

      sent = last_sent_payload
      expect(sent['type']).to eq('response.create')
      expect(sent['model']).to eq('gpt-4o')
    end

    it 'strips :stream from the payload' do
      payload = { model: 'gpt-4o', input: [], stream: true }

      with_events(standard_events) do
        ws.call(payload)
      end

      expect(last_sent_payload).not_to have_key('stream')
    end

    it 'yields chunks and returns assembled Message' do
      payload = { model: 'gpt-4o', input: [] }
      chunks = []

      message = with_events(standard_events(text_deltas: %w[Hello world])) do
        ws.call(payload) { |chunk| chunks << chunk }
      end

      expect(chunks.select(&:content).map(&:content)).to eq(%w[Hello world])
      expect(message).to be_a(RubyLLM::Message)
      expect(message.content).to eq('Helloworld')
      expect(message.response_id).to eq('resp_ws_test')
    end
  end

  describe '#warmup' do
    before { connect_ws! }

    it 'sends generate: false' do
      completed = { 'type' => 'response.completed', 'response' => { 'id' => 'resp_warmup', 'model' => 'gpt-4o' } }

      with_events([completed]) do
        ws.warmup(model: 'gpt-4o')
      end

      payload = last_sent_payload
      expect(payload['type']).to eq('response.create')
      expect(payload['generate']).to be false
      expect(payload['model']).to eq('gpt-4o')
    end
  end

  describe '#disconnect' do
    it 'closes the connection' do
      connect_ws!

      expect(ws).to be_connected
      ws.disconnect
      expect(ws).not_to be_connected
    end
  end

  describe '#create_response without connection' do
    it 'raises ConnectionError' do
      expect do
        ws.create_response(model: 'gpt-4o', input: [])
      end.to raise_error(described_class::ConnectionError, /not connected/)
    end
  end

  describe 'connection drop during response' do
    before { connect_ws! }

    it 'returns partial result when connection closes mid-stream' do
      result = nil
      thread = Thread.new do
        result = ws.create_response(model: 'gpt-4o', input: [])
      end

      # Wait until the queue is installed (meaning create_response is listening)
      Thread.pass until ws.instance_variable_get(:@message_queue)

      push_events({ 'type' => 'response.output_text.delta', 'delta' => 'partial' })
      mock_ws_client.emit(:close)

      thread.join(5)
      expect(result.content).to eq('partial')
    end
  end

  describe 'namespace access' do
    it 'is accessible via RubyLLM::ResponsesAPI::WebSocket' do
      expect(RubyLLM::ResponsesAPI::WebSocket).to eq(described_class)
    end
  end
end
