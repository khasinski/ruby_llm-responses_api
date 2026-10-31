# frozen_string_literal: true

require 'spec_helper'
require 'active_record'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :persistence_test_chats, force: true do |t|
    t.boolean :cancelled, default: false
    t.string :claim_token
    t.datetime :claimed_until
    t.integer :ruby_llm_model_id
    t.timestamps
  end
  create_table :persistence_test_messages, force: true do |t|
    t.integer :chat_id
    t.string :role
    t.text :content
    t.string :response_id
    t.string :finish_reason
    t.text :thinking_text
    t.text :thinking_signature
    t.json :citations
    t.json :server_tool_calls
    t.json :raw_content
    t.json :raw_reasoning
    t.timestamps
  end
  create_table :ruby_llm_models, force: true do |t|
    %i[model_id provider name family].each { |column| t.string column }
    t.datetime :model_created_at
    t.datetime :unlisted_at
    t.date :knowledge_cutoff
    t.integer :context_window
    t.integer :max_output_tokens
    %i[modalities pricing metadata].each { |column| t.json column, default: {} }
    t.json :capabilities, default: []
    t.timestamps
  end
  create_table :ruby_llm_usages, force: true do |t|
    %i[chat message owner].each { |name| t.references name, polymorphic: true }
    %i[operation provider model status].each { |column| t.string column }
    %i[input output cache_read cache_write thinking].each { |name| t.integer "#{name}_tokens" }
    %i[input output cache_read cache_write thinking total].each { |name| t.decimal "#{name}_cost" }
    t.json :server_tool_use
    t.timestamps
  end
  create_table :ruby_llm_tool_calls, force: true do |t|
    t.references :message, polymorphic: true
    t.references :result, polymorphic: true
    %i[tool_call_id name approval thought_signature].each { |column| t.string column }
    t.boolean :remote, default: false
    %i[arguments mcp_state mcp_result].each { |column| t.json column }
    t.timestamps
  end
end

%w[record model usage tool_call batch acts_as].each { |name| require "ruby_llm/active_record/#{name}" }
registry_store = RubyLLM.config.model_registry_store
batch_store = RubyLLM.config.batch_store
ActiveRecord::Base.include(RubyLLM::ActiveRecord::ActsAs)
RubyLLM.config.model_registry_store = registry_store
RubyLLM.config.batch_store = batch_store
RubyLLM::Providers::OpenAIResponses.apply_active_record_extensions!

class PersistenceTestChat < ActiveRecord::Base
  acts_as_chat message_class: 'PersistenceTestMessage', messages_foreign_key: :chat_id
end

class PersistenceTestMessage < ActiveRecord::Base
  acts_as_message chat_class: 'PersistenceTestChat', chat_foreign_key: :chat_id
end

RSpec.describe 'ActiveRecord persistence on RubyLLM 2.1' do
  before do
    PersistenceTestMessage.delete_all
    PersistenceTestChat.delete_all
    RubyLLM::ActiveRecord::Usage.delete_all
    RubyLLM::ActiveRecord::ToolCall.delete_all
  end

  def stub_reply(id)
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return(
      status: 200, body: JSON.generate(sample_completion_response.merge('id' => id)),
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  it 'persists an answer with its response_id and resumes after a fresh database load' do
    stub_reply('resp_first')
    chat = PersistenceTestChat.create!(model: 'gpt-4o', provider: :openai_responses)
    chat.ask('First')
    expect(chat.messages.last.response_id).to eq('resp_first')
    expect(chat.messages.last.to_llm.tokens.input).to eq(10)
    expect(chat.messages.last.to_llm.content).to include('Hello')
    stub_reply('resp_second')
    PersistenceTestChat.find(chat.id).ask('Second')
    expect(a_request(:post, 'https://api.openai.com/v1/responses').with do |request|
      body = JSON.parse(request.body)
      body['previous_response_id'] == 'resp_first' && body['input'] == [{ 'role' => 'user', 'content' => 'Second' }]
    end).to have_been_made.once
  end

  it 'saves a streamed response ID before resuming the persisted chat' do
    events = [
      { 'type' => 'response.output_text.delta', 'delta' => 'Hello' },
      { 'type' => 'response.completed', 'response' => sample_completion_response }
    ]
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return(
      status: 200, body: build_sse_body(events), headers: { 'Content-Type' => 'text/event-stream' }
    )
    chat = PersistenceTestChat.create!(model: 'gpt-4o', provider: :openai_responses)
    chat.ask('First') { |_chunk| }
    expect(chat.messages.last.reload.response_id).to eq('resp_123')
    expect(chat.messages.last.to_llm.tokens.input).to eq(10)
    stub_reply('resp_second')
    PersistenceTestChat.find(chat.id).ask('Second')
    expect(a_request(:post, 'https://api.openai.com/v1/responses').with do |request|
      body = JSON.parse(request.body)
      body['previous_response_id'] == 'resp_123' && body['input'] == [{ 'role' => 'user', 'content' => 'Second' }]
    end).to have_been_made.once
  end

  it 'preserves native reasoning, citations, tool records, and raw content when restoring response_id' do
    chat = PersistenceTestChat.create!(model: 'gpt-4o', provider: :openai_responses)
    record = chat.messages.create!(role: 'assistant', content: 'Answer', response_id: 'resp_saved',
                                   thinking_text: 'Reason', thinking_signature: 'encrypted',
                                   raw_content: [{ type: 'shell_call', id: 'shell_1' }],
                                   server_tool_calls: [{ type: 'shell_call', id: 'shell_1',
                                                         raw: { status: 'completed' } }],
                                   citations: [{ type: 'url', url: 'https://example.com', title: 'Source' }])
    record.ruby_llm_tool_calls.create!(tool_call_id: 'call_1', name: 'weather', arguments: { city: 'Warsaw' })
    message = record.reload.to_llm
    expect(message.response_id).to eq('resp_saved')
    expect(message.thinking.signature).to eq('encrypted')
    expect(message.citations.first.url).to eq('https://example.com')
    expect(message.server_tool_calls.first.id).to eq('shell_1')
    expect(message.raw_content.first['type']).to eq('shell_call')
    expect(message.tool_calls['call_1'].arguments).to eq('city' => 'Warsaw')
  end

  it 'can persist and restore messages without a response_id column' do
    PersistenceTestMessage.ignored_columns = ['response_id']
    stub_reply('resp_not_saved')
    chat = PersistenceTestChat.create!(model: 'gpt-4o', provider: :openai_responses)
    chat.ask('Hello')
    expect(chat.messages.last.reload.to_llm.response_id).to be_nil
  ensure
    PersistenceTestMessage.ignored_columns = []
  end
end
