# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'RubyLLM native Responses compatibility' do
  native_responses =
    defined?(RubyLLM::Protocols::Responses) &&
    defined?(RubyLLM::Providers::OpenAI)

  if native_responses
    require 'active_record'
    require 'ruby_llm/active_record/acts_as'
    require 'ruby_llm/active_record/chat_methods'
    require 'ruby_llm/active_record/message_methods'
    require 'ruby_llm/active_record/model_methods'
    require 'ruby_llm/active_record/tool_call_methods'

    ActiveRecord::Base.establish_connection(
      adapter: 'sqlite3',
      database: ':memory:'
    )

    ActiveRecord::Schema.verbose = false
    ActiveRecord::Schema.define do
      create_table :native_persistence_models, force: true do |t|
        t.string :model_id, null: false
        t.string :provider, null: false
        t.string :name, null: false
        t.string :family
        t.datetime :model_created_at
        t.integer :context_window
        t.integer :max_output_tokens
        t.datetime :knowledge_cutoff
        t.json :modalities
        t.json :capabilities
        t.json :pricing
        t.json :metadata
      end

      create_table :native_persistence_chats, force: true do |t|
        t.integer :model_record_id
        t.timestamps
      end

      create_table :native_persistence_messages, force: true do |t|
        t.integer :native_persistence_chat_id
        t.integer :model_record_id
        t.integer :native_persistence_tool_call_id
        t.string :role, null: false
        t.text :content
        t.integer :input_tokens
        t.integer :output_tokens
        t.string :response_id
        t.timestamps
      end

      create_table :native_persistence_tool_calls, force: true do |t|
        t.integer :native_persistence_message_id
        t.integer :native_persistence_result_id
        t.string :tool_call_id
        t.string :name
        t.json :arguments
        t.timestamps
      end
    end

    class NativePersistenceModel < ActiveRecord::Base
      include RubyLLM::ActiveRecord::ActsAs

      acts_as_model chats: :native_persistence_chats, chat_class: 'NativePersistenceChat',
                    chats_foreign_key: :model_record_id
    end

    class NativePersistenceChat < ActiveRecord::Base
      include RubyLLM::ActiveRecord::ActsAs

      acts_as_chat messages: :native_persistence_messages, message_class: 'NativePersistenceMessage',
                   messages_foreign_key: :native_persistence_chat_id,
                   model: :model_record, model_class: 'NativePersistenceModel',
                   model_foreign_key: :model_record_id
    end

    class NativePersistenceMessage < ActiveRecord::Base
      include RubyLLM::ActiveRecord::ActsAs

      acts_as_message chat: :chat, chat_class: 'NativePersistenceChat',
                      chat_foreign_key: :native_persistence_chat_id,
                      tool_calls: :native_persistence_tool_calls,
                      tool_call_class: 'NativePersistenceToolCall',
                      tool_calls_foreign_key: :native_persistence_message_id,
                      model: :model_record, model_class: 'NativePersistenceModel',
                      model_foreign_key: :model_record_id
    end

    class NativePersistenceToolCall < ActiveRecord::Base
      include RubyLLM::ActiveRecord::ActsAs

      acts_as_tool_call message: :message, message_class: 'NativePersistenceMessage',
                        message_foreign_key: :native_persistence_message_id,
                        result: :result, result_class: 'NativePersistenceMessage',
                        result_foreign_key: :native_persistence_tool_call_id
    end

    let(:config) do
      RubyLLM::Configuration.new.tap do |c|
        c.openai_api_key = 'test-api-key'
      end
    end
    let(:model) do
      RubyLLM::Model::Info.new(
        id: 'gpt-4o',
        provider: 'openai',
        family: 'gpt4',
        modality: 'text',
        context_window: 128_000
      )
    end
    let(:provider) { RubyLLM::Providers::OpenAI.new(config) }
    let(:protocol) { RubyLLM::Protocols::Responses.new(provider, model) }

    before do
      RubyLLM.configure do |c|
        c.openai_api_key = 'test-api-key'
      end
    end

    it 'keeps provider: :openai_responses working for RubyLLM.chat' do
      chat = RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses, assume_model_exists: true)

      expect(chat.instance_variable_get(:@provider)).to be_a(RubyLLM::Providers::OpenAI)
    end

    it 'keeps provider: "openai_responses" working for persisted provider strings' do
      chat = RubyLLM.chat(model: 'gpt-4o', provider: 'openai_responses', assume_model_exists: true)

      expect(chat.instance_variable_get(:@provider)).to be_a(RubyLLM::Providers::OpenAI)
    end

    it 'restores ActiveRecord chats whose model record still stores openai_responses' do
      model_record = NativePersistenceModel.create!(
        model_id: 'gpt-4o',
        provider: 'openai_responses',
        name: 'GPT-4o',
        family: 'gpt',
        context_window: 128_000,
        max_output_tokens: 16_384,
        modalities: {},
        capabilities: [],
        pricing: {},
        metadata: {}
      )
      chat_record = NativePersistenceChat.create!(model_record: model_record)
      chat_record.native_persistence_messages.create!(role: 'user', content: 'Hello')

      llm_chat = chat_record.reload.to_llm

      expect(llm_chat).to be_a(RubyLLM::Chat)
      expect(llm_chat.instance_variable_get(:@provider)).to be_a(RubyLLM::Providers::OpenAI)
      expect(llm_chat.messages.map(&:content)).to eq(['Hello'])
    end

    it 'does not break default RubyLLM model resolution when provider is omitted' do
      expect do
        RubyLLM::Models.resolve('gpt-4o', config: RubyLLM.config)
      end.not_to raise_error
    end

    it 'keeps provider: :openai_responses working for RubyLLM.batch' do
      batch = RubyLLM.batch(model: 'gpt-4o', provider: :openai_responses)

      expect(batch.instance_variable_get(:@provider)).to be_a(RubyLLM::Providers::OpenAI)
    end

    it 'keeps provider: :openai_responses working for RubyLLM.batches' do
      provider_instance = instance_double(RubyLLM::Providers::OpenAI, list_batches: { 'data' => [] })

      allow(RubyLLM::Providers::OpenAI).to receive(:new).and_return(provider_instance)

      expect(RubyLLM.batches(provider: :openai_responses)).to eq({ 'data' => [] })
      expect(provider_instance).to have_received(:list_batches)
    end

    it 'keeps transport: :websocket available through with_params-style provider params' do
      response = RubyLLM::Message.new(role: :assistant, content: 'Hello over WebSocket')
      websocket = instance_double(
        RubyLLM::Providers::OpenAIResponses::WebSocket,
        connected?: false,
        connect: true,
        call: response
      )

      allow(RubyLLM::Providers::OpenAIResponses::WebSocket).to receive(:new).and_return(websocket)

      result = provider.complete(
        [RubyLLM::Message.new(role: :user, content: 'Hello')],
        tools: {},
        temperature: nil,
        model: model,
        params: { transport: :websocket }
      )

      expect(result).to eq(response)
      expect(websocket).to have_received(:connect)
      expect(websocket).to have_received(:call) do |payload|
        expect(payload).not_to have_key(:transport)
        expect(payload[:stream]).to be true
      end
    end

    it 'stores the OpenAI response id on parsed assistant messages' do
      raw_response = instance_double(
        Faraday::Response,
        body: {
          'id' => 'resp_123',
          'output' => [
            {
              'type' => 'message',
              'role' => 'assistant',
              'content' => [{ 'type' => 'output_text', 'text' => 'Hello' }]
            }
          ]
        }
      )

      message = protocol.__send__(:parse_completion_response, raw_response)

      expect(message.response_id).to eq('resp_123')
    end

    it 'sends the next native turn with previous_response_id and only unchained messages' do
      messages = [
        RubyLLM::Message.new(role: :system, content: 'Be brief.'),
        RubyLLM::Message.new(role: :user, content: 'First'),
        RubyLLM::Message.new(role: :assistant, content: 'First answer', response_id: 'resp_abc'),
        RubyLLM::Message.new(role: :user, content: 'Second')
      ]

      payload = protocol.__send__(
        :render_payload,
        messages,
        tools: {},
        temperature: nil,
        model: model,
        stream: false,
        schema: nil,
        thinking: nil,
        citations: false,
        tool_prefs: nil
      )

      expect(payload[:previous_response_id]).to eq('resp_abc')
      expect(payload[:instructions]).to eq('Be brief.')
      expect(payload[:input].map { |item| item[:content] }).to eq(['Second'])
      expect(payload).not_to have_key(:store)
    end
  else
    it 'skips the native compatibility contract without RubyLLM native Responses support' do
      skip 'RubyLLM native Responses protocol is not available'
    end
  end
end
