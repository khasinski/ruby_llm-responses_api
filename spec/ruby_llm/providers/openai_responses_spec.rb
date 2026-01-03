# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::OpenAIResponses do
  let(:config) do
    RubyLLM::Configuration.new.tap do |c|
      c.openai_api_key = 'test-api-key'
    end
  end

  let(:provider) { described_class.new(config) }

  describe '.configuration_requirements' do
    it 'requires openai_api_key' do
      expect(described_class.configuration_requirements).to eq(%i[openai_api_key])
    end
  end

  describe '.slug' do
    it 'returns :openai_responses' do
      expect(described_class.slug).to eq(:openai_responses)
    end
  end

  describe '#api_base' do
    it 'returns the default OpenAI API base' do
      expect(provider.api_base).to eq('https://api.openai.com/v1')
    end

    it 'uses custom api_base from config' do
      config.openai_api_base = 'https://custom.api.com/v1'
      expect(provider.api_base).to eq('https://custom.api.com/v1')
    end
  end

  describe '#headers' do
    it 'includes Authorization header' do
      expect(provider.headers['Authorization']).to eq('Bearer test-api-key')
    end

    it 'includes organization header when set' do
      config.openai_organization_id = 'org-123'
      expect(provider.headers['OpenAI-Organization']).to eq('org-123')
    end

    it 'excludes nil headers' do
      expect(provider.headers).not_to have_key('OpenAI-Organization')
    end
  end
end
