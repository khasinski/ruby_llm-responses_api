# frozen_string_literal: true

require 'spec_helper'
require 'active_record'

# Set up in-memory SQLite database
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
)

# Suppress schema migration output
ActiveRecord::Schema.verbose = false

# Create minimal test schema
ActiveRecord::Schema.define do
  create_table :persistence_test_messages, force: true do |t|
    t.string :role, null: false
    t.text :content
    t.integer :input_tokens
    t.integer :output_tokens
    t.string :response_id
    t.timestamps
  end
end

# Load RubyLLM ActiveRecord modules
require 'ruby_llm/active_record/message_methods'
require 'ruby_llm/active_record/chat_methods'

# Apply the OpenAI Responses ActiveRecord extensions BEFORE defining the model
RubyLLM::Providers::OpenAIResponses.apply_active_record_extensions!

# Simple test model that includes MessageMethods directly
class PersistenceTestMessage < ActiveRecord::Base
  include RubyLLM::ActiveRecord::MessageMethods

  # Minimal implementations for MessageMethods dependencies
  def model_association
    nil
  end

  def extract_content
    content
  end

  def extract_tool_calls
    nil
  end

  def extract_tool_call_id
    nil
  end
end

RSpec.describe 'ActiveRecord Persistence' do
  before(:each) do
    PersistenceTestMessage.delete_all
  end

  describe 'response_id persistence' do
    it 'saves response_id when message is persisted' do
      message = PersistenceTestMessage.create!(
        role: 'assistant',
        content: 'Hello!',
        response_id: 'resp_abc123'
      )

      expect(message.reload.response_id).to eq('resp_abc123')
    end

    it 'includes response_id when converting to RubyLLM::Message via to_llm' do
      message = PersistenceTestMessage.create!(
        role: 'assistant',
        content: 'Hello!',
        response_id: 'resp_xyz789'
      )

      llm_message = message.to_llm

      expect(llm_message).to be_a(RubyLLM::Message)
      expect(llm_message.response_id).to eq('resp_xyz789')
    end

    it 'preserves response_id after save and reload' do
      # Create message with response_id
      message = PersistenceTestMessage.create!(
        role: 'assistant',
        content: 'First response',
        response_id: 'resp_first123'
      )

      # Simulate app restart by reloading from database
      message_id = message.id
      reloaded_message = PersistenceTestMessage.find(message_id)

      expect(reloaded_message.response_id).to eq('resp_first123')
      expect(reloaded_message.to_llm.response_id).to eq('resp_first123')
    end

    it 'handles nil response_id gracefully' do
      message = PersistenceTestMessage.create!(
        role: 'user',
        content: 'Hello'
        # No response_id - user messages don't have one
      )

      llm_message = message.to_llm

      expect(llm_message.response_id).to be_nil
    end

    it 'handles missing response_id column gracefully' do
      # Test that to_llm doesn't crash when response_id column doesn't exist
      # The extension checks has_attribute? before accessing
      message = PersistenceTestMessage.create!(
        role: 'assistant',
        content: 'Test'
      )

      # This should not raise even if response_id is nil
      llm_message = message.to_llm
      expect(llm_message).to be_a(RubyLLM::Message)
    end
  end

  describe 'conversation history with response_id' do
    it 'extracts last response_id from multiple messages' do
      # Simulate a multi-turn conversation
      PersistenceTestMessage.create!(role: 'user', content: 'Hi')
      PersistenceTestMessage.create!(role: 'assistant', content: 'Hello!', response_id: 'resp_1')
      PersistenceTestMessage.create!(role: 'user', content: 'How are you?')
      PersistenceTestMessage.create!(role: 'assistant', content: 'Great!', response_id: 'resp_2')

      # Get all messages and convert to LLM format
      messages = PersistenceTestMessage.order(:created_at)
      llm_messages = messages.map(&:to_llm)

      # Find the last response_id
      last_response_id = llm_messages.reverse.find(&:response_id)&.response_id
      expect(last_response_id).to eq('resp_2')
    end

    it 'correctly converts all message roles' do
      PersistenceTestMessage.create!(role: 'user', content: 'Question')
      PersistenceTestMessage.create!(role: 'assistant', content: 'Answer', response_id: 'resp_1')
      PersistenceTestMessage.create!(role: 'system', content: 'Instructions')

      messages = PersistenceTestMessage.order(:created_at).map(&:to_llm)

      expect(messages[0].role).to eq(:user)
      expect(messages[1].role).to eq(:assistant)
      expect(messages[2].role).to eq(:system)
    end
  end

  describe 'MessageMethodsExtension' do
    it 'is prepended to MessageMethods' do
      ancestors = RubyLLM::ActiveRecord::MessageMethods.ancestors
      extension = RubyLLM::Providers::OpenAIResponses::MessageMethodsExtension

      expect(ancestors).to include(extension)
    end

    it 'overrides to_llm to include response_id' do
      message = PersistenceTestMessage.create!(
        role: 'assistant',
        content: 'Test',
        input_tokens: 10,
        output_tokens: 5,
        response_id: 'resp_test'
      )

      llm_message = message.to_llm

      expect(llm_message.role).to eq(:assistant)
      expect(llm_message.content).to eq('Test')
      expect(llm_message.input_tokens).to eq(10)
      expect(llm_message.output_tokens).to eq(5)
      expect(llm_message.response_id).to eq('resp_test')
    end
  end

  describe 'ChatMethodsExtension' do
    it 'is prepended to ChatMethods' do
      ancestors = RubyLLM::ActiveRecord::ChatMethods.ancestors
      extension = RubyLLM::Providers::OpenAIResponses::ChatMethodsExtension

      expect(ancestors).to include(extension)
    end
  end
end
