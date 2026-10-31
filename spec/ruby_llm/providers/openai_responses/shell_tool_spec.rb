# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Shell tool support' do
  describe RubyLLM::Providers::OpenAIResponses::BuiltInTools do
    let(:built_in) { RubyLLM::Providers::OpenAIResponses::BuiltInTools }

    describe '.shell' do
      it 'creates default shell configuration' do
        tool = built_in.shell
        expect(tool[:type]).to eq('shell')
        expect(tool[:environment][:type]).to eq('container_auto')
      end

      it 'supports container_reference with container_id' do
        tool = built_in.shell(container_id: 'cntr_abc123')
        expect(tool[:environment][:type]).to eq('container_reference')
        expect(tool[:environment][:container_id]).to eq('cntr_abc123')
      end

      it 'supports networking with allowlist' do
        policy = {
          type: 'allowlist',
          allowed_domains: ['pypi.org'],
          domain_secrets: [{ domain: 'pypi.org', name: 'TOKEN', value: 'secret' }]
        }
        tool = built_in.shell(network_policy: policy)
        expect(tool[:environment][:network_policy]).to eq(policy)
      end
    end

    describe '.web_search' do
      it 'creates stable web search configuration by default' do
        tool = built_in.web_search
        expect(tool[:type]).to eq('web_search')
      end

      it 'supports legacy preview web search configuration' do
        tool = built_in.web_search_preview(search_context_size: 'high')
        expect(tool[:type]).to eq('web_search_preview')
        expect(tool[:search_context_size]).to eq('high')
      end
    end

    describe '.parse_shell_call_results' do
      it 'extracts shell_call items from output' do
        output = [
          {
            'type' => 'shell_call',
            'id' => 'sc_123',
            'call_id' => 'call_123',
            'status' => 'completed',
            'action' => { 'commands' => ['ls -la'], 'timeout_ms' => 120_000 },
            'container_id' => 'cntr_abc'
          },
          {
            'type' => 'message',
            'role' => 'assistant',
            'content' => [{ 'type' => 'output_text', 'text' => 'Done.' }]
          }
        ]

        results = built_in.parse_shell_call_results(output)
        expect(results.length).to eq(1)
        expect(results.first[:id]).to eq('sc_123')
        expect(results.first[:call_id]).to eq('call_123')
        expect(results.first[:status]).to eq('completed')
        expect(results.first[:action]['commands']).to eq(['ls -la'])
        expect(results.first[:container_id]).to eq('cntr_abc')
      end

      it 'returns empty array when no shell calls' do
        output = [{ 'type' => 'message', 'content' => [] }]
        expect(built_in.parse_shell_call_results(output)).to be_empty
      end
    end
  end
end
