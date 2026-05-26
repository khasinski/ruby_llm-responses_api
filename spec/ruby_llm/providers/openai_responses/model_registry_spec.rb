# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::OpenAIResponses::ModelRegistry do
  describe 'registered models' do
    it 'includes GPT-5.5 with current Responses API capabilities' do
      model = RubyLLM::Models.instance.all.find do |m|
        m.id == 'gpt-5.5' && m.provider == 'openai_responses'
      end

      expect(model).not_to be_nil
      expect(model.context_window).to eq(1_050_000)
      expect(model.max_output_tokens).to eq(128_000)
      expect(model.capabilities).to include(
        'reasoning',
        'web_search',
        'file_search',
        'image_generation',
        'code_interpreter',
        'shell',
        'apply_patch',
        'computer_use',
        'mcp'
      )
    end
  end
end
