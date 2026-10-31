# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::OpenAIResponses::ModelRegistry do
  it 'reuses current OpenAI capabilities, limits and pricing' do
    source = RubyLLM.models.find('gpt-4o', provider: :openai)
    model = RubyLLM.models.find('gpt-4o', provider: :openai_responses)
    expect(model.to_h).to eq(source.to_h.merge(provider: 'openai_responses'))
  end

  it 'can filter and find the provider catalog without a separate model snapshot' do
    catalog = RubyLLM.models.by_provider(:openai_responses)
    native = RubyLLM.models.by_provider(:openai)
    expect(catalog.map(&:id)).to include(*native.map(&:id))
    expect(catalog.find('gpt-4o').provider).to eq('openai_responses')
    expect(catalog.map(&:provider).uniq).to eq(['openai_responses'])
  end

  it 'does not change native provider selection' do
    expect(RubyLLM.models.find('gpt-4o').provider).to eq('openai')
  end

  it 'does not hide unknown models' do
    expect { RubyLLM.models.find('unknown-model', provider: :openai_responses) }
      .to raise_error(RubyLLM::ModelNotFoundError)
  end
end
