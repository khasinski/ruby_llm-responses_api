# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'WebSocket integration', :live_ws do
  let(:api_key) { ENV.fetch('OPENAI_API_KEY') }
  let(:ws) { RubyLLM::ResponsesAPI::WebSocket.new(api_key: api_key) }

  after { ws.disconnect if ws.connected? }

  it 'connects, sends a message, and receives a streamed response' do
    ws.connect

    chunks = []
    message = ws.create_response(
      model: 'gpt-4o-mini',
      input: [
        {
          type: 'message',
          role: 'user',
          content: [{ type: 'input_text', text: 'Say "hello" and nothing else.' }]
        }
      ]
    ) do |chunk|
      chunks << chunk
    end

    expect(message).to be_a(RubyLLM::Message)
    expect(message.content).to be_a(String)
    expect(message.content.downcase).to include('hello')
    expect(chunks).not_to be_empty
    expect(ws.last_response_id).to start_with('resp_')
  end

  it 'supports multi-turn with previous_response_id continuation' do
    ws.connect

    ws.create_response(
      model: 'gpt-4o-mini',
      input: [
        {
          type: 'message',
          role: 'user',
          content: [{ type: 'input_text', text: 'My name is Alice.' }]
        }
      ]
    )

    first_id = ws.last_response_id
    expect(first_id).not_to be_nil

    message = ws.create_response(
      model: 'gpt-4o-mini',
      input: [
        {
          type: 'message',
          role: 'user',
          content: [{ type: 'input_text', text: "What's my name?" }]
        }
      ]
    )

    expect(message.content.downcase).to include('alice')
    expect(ws.last_response_id).not_to eq(first_id)
  end
end
