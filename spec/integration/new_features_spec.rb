# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'New Features Integration', :vcr do
  # Shell tool requires GPT-5 family models
  let(:shell_model) { 'gpt-5.2' }
  let(:model) { 'gpt-4o-mini' }

  describe 'Shell Tool' do
    it 'executes commands in a hosted container', vcr: { cassette_name: 'shell_container_auto' } do
      chat = RubyLLM.chat(model: shell_model, provider: :openai_responses)
      chat.with_provider_options(
        tools: [{ type: 'shell', environment: { type: 'container_auto' } }]
      )

      response = chat.ask('Run: echo "hello from shell"')

      expect(response).to be_a(RubyLLM::Message)
      expect(response.content.downcase).to include('hello')
    end

    it 'executes commands using helper method', vcr: { cassette_name: 'shell_helper' } do
      chat = RubyLLM.chat(model: shell_model, provider: :openai_responses)
      tool = RubyLLM::ResponsesAPI::BuiltInTools.shell
      chat.with_provider_options(tools: [tool])

      response = chat.ask('Run: pwd')

      expect(response).to be_a(RubyLLM::Message)
      expect(response.content).to match(%r{/})
    end
  end

  describe 'Server-Side Compaction' do
    it 'accepts compaction params without error', vcr: { cassette_name: 'compaction_basic' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)
      chat.with_provider_options(
        **RubyLLM::ResponsesAPI::Compaction.compaction_params(compact_threshold: 200_000)
      )

      response = chat.ask('Say hello.')

      expect(response).to be_a(RubyLLM::Message)
      expect(response.content.downcase).to include('hello')
    end

    it 'accepts context_management directly', vcr: { cassette_name: 'compaction_direct' } do
      chat = RubyLLM.chat(model: model, provider: :openai_responses)
      chat.with_provider_options(
        context_management: [{ type: 'compaction', compact_threshold: 100_000 }]
      )

      response = chat.ask('What is 1 + 1? Reply with just the number.')

      expect(response).to be_a(RubyLLM::Message)
      expect(response.content).to include('2')
    end
  end

  describe 'Containers API' do
    it 'creates and retrieves a container', vcr: { cassette_name: 'containers_create_retrieve' } do
      # Get the provider instance via the chat object's internal provider
      chat = RubyLLM.chat(model: model, provider: :openai_responses)
      provider = chat.instance_variable_get(:@provider)

      container = provider.create_container(
        name: 'rubyllm-test-container',
        expires_after: { anchor: 'last_active_at', minutes: 10 }
      )

      expect(container).to be_a(Hash)
      expect(container['id']).to start_with('cntr_')
      expect(container['name']).to eq('rubyllm-test-container')
      expect(container['object']).to eq('container')

      # Retrieve
      retrieved = provider.retrieve_container(container['id'])
      expect(retrieved['id']).to eq(container['id'])

      # Cleanup
      provider.delete_container(container['id'])
    end
  end
end
