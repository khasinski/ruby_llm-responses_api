# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::OpenAIResponses::ChatExtension do
  describe 'dispatching built-in tool events to on_tool_call / on_tool_result' do
    let(:chat) { RubyLLM::Chat.new(model: 'gpt-4o', provider: :openai_responses, assume_model_exists: true) }
    let(:event) do
      {
        tool_call: RubyLLM::ToolCall.new(id: 'ws_1', name: 'web_search', arguments: {}),
        result: { id: 'ws_1', status: 'completed', results: [] }
      }
    end

    it 'fires on_tool_call and on_tool_result when an assistant message carries built_in_tool_events' do
      seen_calls = []
      seen_results = []
      chat.on_tool_call { |tc| seen_calls << tc }
      chat.on_tool_result { |r| seen_results << r }

      message = RubyLLM::Message.new(
        role: :assistant,
        content: 'Here are the results.',
        built_in_tool_events: [event]
      )

      chat.add_message(message)

      expect(seen_calls.map(&:name)).to eq(['web_search'])
      expect(seen_results.map { |r| r[:id] }).to eq(['ws_1'])
    end

    it 'does nothing when no built-in events are present' do
      called = false
      chat.on_tool_call { called = true }

      chat.add_message(RubyLLM::Message.new(role: :assistant, content: 'plain'))

      expect(called).to be false
    end

    it 'is a no-op when no callbacks are registered' do
      message = RubyLLM::Message.new(
        role: :assistant,
        content: 'ok',
        built_in_tool_events: [event]
      )

      expect { chat.add_message(message) }.not_to raise_error
    end
  end
end
