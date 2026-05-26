# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::OpenAIResponses::BuiltInTools do
  describe '.extract_events' do
    it 'returns [] for empty or non-array output' do
      expect(described_class.extract_events([])).to eq([])
      expect(described_class.extract_events(nil)).to eq([])
    end

    it 'ignores plain message outputs that are not built-in tool calls' do
      output = [
        { 'type' => 'message', 'role' => 'assistant', 'content' => [] },
        { 'type' => 'function_call', 'call_id' => 'c1', 'name' => 'x', 'arguments' => '{}' }
      ]

      expect(described_class.extract_events(output)).to eq([])
    end

    it 'surfaces a web_search_call as a tool_call / result event' do
      output = [
        {
          'type' => 'web_search_call',
          'id' => 'ws_1',
          'status' => 'completed',
          'action' => { 'type' => 'search', 'query' => 'ruby gems 4.0' },
          'results' => [{ 'url' => 'https://example.com', 'title' => 'Example' }]
        }
      ]

      events = described_class.extract_events(output)

      expect(events.size).to eq(1)
      call = events.first[:tool_call]
      expect(call).to be_a(RubyLLM::ToolCall)
      expect(call.id).to eq('ws_1')
      expect(call.name).to eq('web_search')

      result = events.first[:result]
      expect(result[:id]).to eq('ws_1')
      expect(result[:status]).to eq('completed')
      expect(result[:results]).to be_an(Array)
    end

    it 'surfaces a code_interpreter_call with its code' do
      output = [
        {
          'type' => 'code_interpreter_call',
          'id' => 'ci_1',
          'status' => 'completed',
          'code' => 'puts 1 + 1',
          'container_id' => 'cnt_abc',
          'results' => [{ 'type' => 'logs', 'logs' => '2' }]
        }
      ]

      events = described_class.extract_events(output)
      call = events.first[:tool_call]

      expect(call.name).to eq('code_interpreter')
      expect(call.arguments).to eq({ code: 'puts 1 + 1', container_id: 'cnt_abc' })
      expect(events.first[:result][:results]).to be_an(Array)
    end

    it 'surfaces file_search, image_generation, shell, apply_patch, and mcp calls' do
      output = [
        { 'type' => 'file_search_call', 'id' => 'fs_1', 'status' => 'completed', 'queries' => %w[ruby] },
        { 'type' => 'image_generation_call', 'id' => 'ig_1', 'status' => 'completed', 'result' => 'b64...' },
        { 'type' => 'shell_call', 'id' => 'sh_1', 'status' => 'completed', 'action' => { 'command' => %w[ls] } },
        { 'type' => 'apply_patch_call', 'id' => 'ap_1', 'status' => 'completed',
          'operation' => { 'type' => 'create' } },
        { 'type' => 'mcp_call', 'id' => 'mcp_1', 'status' => 'completed', 'name' => 'do_thing',
          'arguments' => '{}', 'server_label' => 'my-server' }
      ]

      names = described_class.extract_events(output).map { |e| e[:tool_call].name }
      expect(names).to eq(%w[file_search image_generation shell apply_patch mcp])
    end
  end
end
