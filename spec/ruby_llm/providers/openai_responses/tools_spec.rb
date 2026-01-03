# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::OpenAIResponses::Tools do
  let(:tools_module) { RubyLLM::Providers::OpenAIResponses::Tools }

  describe '.tool_for' do
    it 'converts a RubyLLM tool to function format' do
      tool = instance_double(
        RubyLLM::Tool,
        name: 'get_weather',
        description: 'Get weather for a location',
        params_schema: nil,
        parameters: {},
        provider_params: {}
      )

      result = tools_module.tool_for(tool)

      expect(result[:type]).to eq('function')
      expect(result[:name]).to eq('get_weather')
      expect(result[:description]).to eq('Get weather for a location')
    end

    it 'returns built-in tool configs as-is' do
      built_in = { type: 'web_search_preview' }
      result = tools_module.tool_for(built_in)

      expect(result).to eq(built_in)
    end
  end

  describe 'built-in tool helpers' do
    describe '.web_search_tool' do
      it 'creates web search configuration' do
        tool = tools_module.web_search_tool
        expect(tool[:type]).to eq('web_search_preview')
      end

      it 'includes search_context_size when provided' do
        tool = tools_module.web_search_tool(search_context_size: 'high')
        expect(tool[:search_context_size]).to eq('high')
      end
    end

    describe '.code_interpreter_tool' do
      it 'creates code interpreter configuration' do
        tool = tools_module.code_interpreter_tool
        expect(tool[:type]).to eq('code_interpreter')
        expect(tool[:container][:type]).to eq('auto')
      end
    end

    describe '.mcp_tool' do
      it 'creates MCP server configuration' do
        tool = tools_module.mcp_tool(
          server_label: 'github',
          server_url: 'https://api.github.com/mcp'
        )

        expect(tool[:type]).to eq('mcp')
        expect(tool[:server_label]).to eq('github')
        expect(tool[:server_url]).to eq('https://api.github.com/mcp')
        expect(tool[:require_approval]).to eq('never')
      end
    end
  end

  describe '.parse_tool_calls' do
    it 'parses function call outputs' do
      tool_calls = [
        {
          'call_id' => 'call_123',
          'name' => 'get_weather',
          'arguments' => '{"location": "NYC"}'
        }
      ]

      result = tools_module.parse_tool_calls(tool_calls)

      expect(result['call_123'].id).to eq('call_123')
      expect(result['call_123'].name).to eq('get_weather')
      expect(result['call_123'].arguments).to eq({ 'location' => 'NYC' })
    end

    it 'returns nil for empty tool calls' do
      expect(tools_module.parse_tool_calls(nil)).to be_nil
      expect(tools_module.parse_tool_calls([])).to be_nil
    end
  end
end
