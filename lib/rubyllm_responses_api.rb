# frozen_string_literal: true

require 'ruby_llm'
require_relative 'ruby_llm/providers/openai_responses/base'

%w[
  built_in_tools state background compaction containers message_extension
  stream_accumulator chat_extension model_registry active_record_extension
  protocol web_socket batches batch
].each { |name| require_relative "ruby_llm/providers/openai_responses/#{name}" }
require_relative 'ruby_llm/providers/openai_responses'

RubyLLM::Provider.register :openai_responses, RubyLLM::Providers::OpenAIResponses

module RubyLLM
  # Responses-specific helpers. RubyLLM's native batch factory is unchanged.
  module ResponsesAPI
    VERSION = '1.0.0'

    BuiltInTools = Providers::OpenAIResponses::BuiltInTools
    State = Providers::OpenAIResponses::State
    Background = Providers::OpenAIResponses::Background
    Compaction = Providers::OpenAIResponses::Compaction
    Containers = Providers::OpenAIResponses::Containers
    Batches = Providers::OpenAIResponses::Batches
    Batch = Providers::OpenAIResponses::Batch
    WebSocket = Providers::OpenAIResponses::WebSocket

    def self.batch(...)
      Batch.new(...)
    end

    def self.batches(provider: :openai_responses, **)
      RubyLLM::Provider.resolve!(provider).new(RubyLLM.config).list_batches(**)
    end
  end
end
