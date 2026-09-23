# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::OpenAIResponses::StreamAccumulatorExtension do
  let(:accumulator) { RubyLLM::StreamAccumulator.new }
  let(:event) do
    {
      tool_call: RubyLLM::ToolCall.new(id: 'ws_1', name: 'web_search', arguments: {}),
      result: { id: 'ws_1', status: 'completed' }
    }
  end

  def text_chunk(text)
    RubyLLM::Chunk.new(role: :assistant, content: text)
  end

  def event_chunk(events)
    RubyLLM::Chunk.new(role: :assistant, content: nil, built_in_tool_events: events)
  end

  def completed_chunk(response_id)
    RubyLLM::Chunk.new(role: :assistant, content: nil, response_id: response_id)
  end

  it 'forwards built_in_tool_events from chunks to the assembled message' do
    accumulator.add(text_chunk('Hello'))
    accumulator.add(event_chunk([event]))
    accumulator.add(text_chunk(' world'))

    message = accumulator.to_message(nil)

    expect(message.content).to eq('Hello world')
    expect(message.built_in_tool_events.size).to eq(1)
    expect(message.built_in_tool_events.first[:tool_call].name).to eq('web_search')
  end

  it 'does not attach built_in_tool_events when none were observed' do
    accumulator.add(text_chunk('Hi'))

    message = accumulator.to_message(nil)

    expect(message.built_in_tool_events).to be_nil
  end

  it 'concatenates events across multiple chunks' do
    accumulator.add(event_chunk([event]))
    second = {
      tool_call: RubyLLM::ToolCall.new(id: 'ci_1', name: 'code_interpreter', arguments: {}),
      result: { id: 'ci_1', status: 'completed' }
    }
    accumulator.add(event_chunk([second]))

    message = accumulator.to_message(nil)

    expect(message.built_in_tool_events.map { |e| e[:tool_call].name }).to eq(%w[web_search code_interpreter])
  end

  it 'forwards response_id from the completed chunk to the assembled message' do
    accumulator.add(text_chunk('Hello'))
    accumulator.add(completed_chunk('resp_123'))

    message = accumulator.to_message(nil)

    expect(message.response_id).to eq('resp_123')
  end

  it 'does not set response_id when no chunk carried one' do
    accumulator.add(text_chunk('Hi'))

    message = accumulator.to_message(nil)

    expect(message.response_id).to be_nil
  end
end
