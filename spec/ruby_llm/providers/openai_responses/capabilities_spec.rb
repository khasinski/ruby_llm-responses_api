# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::OpenAIResponses::Capabilities do
  let(:capabilities) { RubyLLM::Providers::OpenAIResponses::Capabilities }

  describe '.supports_responses_api?' do
    it 'returns true for GPT-4o models' do
      expect(capabilities.supports_responses_api?('gpt-4o')).to be true
      expect(capabilities.supports_responses_api?('gpt-4o-mini')).to be true
    end

    it 'returns true for GPT-4.1 models' do
      expect(capabilities.supports_responses_api?('gpt-4.1')).to be true
      expect(capabilities.supports_responses_api?('gpt-4.1-mini')).to be true
      expect(capabilities.supports_responses_api?('gpt-4.1-nano')).to be true
    end

    it 'returns true for o-series models' do
      expect(capabilities.supports_responses_api?('o1')).to be true
      expect(capabilities.supports_responses_api?('o3')).to be true
      expect(capabilities.supports_responses_api?('o4-mini')).to be true
    end
  end

  describe '.supports_vision?' do
    it 'returns true for vision-capable models' do
      expect(capabilities.supports_vision?('gpt-4o')).to be true
      expect(capabilities.supports_vision?('gpt-4.1')).to be true
    end
  end

  describe '.reasoning_model?' do
    it 'returns true for o-series models' do
      expect(capabilities.reasoning_model?('o1')).to be true
      expect(capabilities.reasoning_model?('o3')).to be true
      expect(capabilities.reasoning_model?('o4-mini')).to be true
    end

    it 'returns false for GPT models' do
      expect(capabilities.reasoning_model?('gpt-4o')).to be false
    end
  end

  describe '.context_window_for' do
    it 'returns correct context window for GPT-4o' do
      expect(capabilities.context_window_for('gpt-4o')).to eq(128_000)
    end

    it 'returns correct context window for GPT-4.1' do
      expect(capabilities.context_window_for('gpt-4.1')).to eq(1_000_000)
    end
  end

  describe '.normalize_temperature' do
    it 'returns nil for reasoning models' do
      expect(capabilities.normalize_temperature(0.7, 'o1')).to be_nil
      expect(capabilities.normalize_temperature(0.7, 'o3')).to be_nil
    end

    it 'returns temperature for non-reasoning models' do
      expect(capabilities.normalize_temperature(0.7, 'gpt-4o')).to eq(0.7)
    end
  end

  describe '.capabilities_for' do
    it 'includes streaming and function_calling for all models' do
      caps = capabilities.capabilities_for('gpt-4o')
      expect(caps).to include('streaming', 'function_calling')
    end

    it 'includes vision for vision models' do
      caps = capabilities.capabilities_for('gpt-4o')
      expect(caps).to include('vision')
    end

    it 'includes reasoning for o-series models' do
      caps = capabilities.capabilities_for('o3')
      expect(caps).to include('reasoning')
    end
  end
end
