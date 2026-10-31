# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'WebSocket through the native protocol' do
  let(:chat) { RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses) }
  let(:socket) { instance_double(RubyLLM::ResponsesAPI::WebSocket, connected?: true) }
  let(:payloads) { [] }
  let(:response) { sample_completion_response }

  before do
    allow(RubyLLM::ResponsesAPI::WebSocket).to receive(:new).and_return(socket)
    allow(socket).to receive(:stream_events) do |payload, &block|
      payloads << payload
      block.call('type' => 'response.output_text.delta', 'delta' => 'Hello')
      block.call('type' => 'response.completed', 'response' => response)
      nil
    end
    chat.with_provider_options(transport: :websocket)
  end

  it 'uses native rendering, hooks, headers, tool options and accounting without an HTTP request' do
    chat.with_headers('X-Test' => 'migration').with_max_output_tokens(50)
    chat.before_request { |payload| payload[:metadata] = { source: 'hook' } }
    chat.with_provider_tools(:web_search)
    result = chat.ask('Hello')
    expect(result.content).to eq('Hello')
    expect(result.response_id).to eq('resp_123')
    expect(result.raw.body).to eq(response)
    expect(result.tokens.input).to eq(10)
    expect(chat.usage_entries.size).to eq(1)
    expect(chat.usage_entries.first).to be_succeeded
    expect(chat.usage_entries.first.tokens.input).to eq(10)
    expect(payloads.first).to include(store: true, max_output_tokens: 50, metadata: { source: 'hook' })
    expect(payloads.first[:tools]).to include(type: 'web_search')
    expect(payloads.first).not_to have_key(:transport)
    expect(RubyLLM::ResponsesAPI::WebSocket).to have_received(:new).with(
      hash_including(headers: { 'X-Test' => 'migration' })
    )
  end

  it 'chains streamed turns using only new messages' do
    chunks = []
    chat.ask('First') { |chunk| chunks << chunk }
    chat.ask('Second') { |_chunk| }
    expect(chunks.filter_map(&:content)).to eq(['Hello'])
    expect(payloads.last[:previous_response_id]).to eq('resp_123')
    expect(payloads.last[:input]).to eq([{ role: 'user', content: 'Second' }])
    expect(chat.usage_entries.size).to eq(2)
  end

  it 'keeps store false stateless across multiple calls' do
    chat.with_provider_options(transport: :websocket, store: false)
    expect(chat.ask('First').response_id).to be_nil
    chat.ask('Second') { |_chunk| }
    expect(chat.messages.last.response_id).to be_nil
    expect(payloads.last).not_to have_key(:previous_response_id)
    expect(payloads.last[:input].size).to eq(3)
  end

  it 'records failed attempts and does not append an incomplete answer on disconnect' do
    allow(socket).to receive(:stream_events).and_raise(RubyLLM::ResponsesAPI::WebSocket::ConnectionError, 'closed')
    expect { chat.ask('Hello') }.to raise_error(RubyLLM::ResponsesAPI::WebSocket::ConnectionError)
    expect(chat.messages.map(&:role)).to eq([:user])
    expect(chat.usage_entries.first).to be_failed
  end

  it 'reconnects when handshake headers change' do
    allow(socket).to receive(:disconnect)
    chat.ask('First')
    chat.with_headers('X-Test' => 'new').ask('Second')
    expect(socket).to have_received(:disconnect).once
    expect(RubyLLM::ResponsesAPI::WebSocket).to have_received(:new).twice
  end
end
