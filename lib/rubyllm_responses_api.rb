# frozen_string_literal: true

require 'ruby_llm'

# Provider class must be loaded first to define the class
require_relative 'ruby_llm/providers/openai_responses/base'

# Core modules
require_relative 'ruby_llm/providers/openai_responses/capabilities'
require_relative 'ruby_llm/providers/openai_responses/media'
require_relative 'ruby_llm/providers/openai_responses/tools'
require_relative 'ruby_llm/providers/openai_responses/models'
require_relative 'ruby_llm/providers/openai_responses/streaming'
require_relative 'ruby_llm/providers/openai_responses/chat'

# Advanced features
require_relative 'ruby_llm/providers/openai_responses/built_in_tools'
require_relative 'ruby_llm/providers/openai_responses/state'
require_relative 'ruby_llm/providers/openai_responses/background'
require_relative 'ruby_llm/providers/openai_responses/compaction'
require_relative 'ruby_llm/providers/openai_responses/containers'
require_relative 'ruby_llm/providers/openai_responses/batches'
require_relative 'ruby_llm/providers/openai_responses/batch'
require_relative 'ruby_llm/providers/openai_responses/message_extension'
require_relative 'ruby_llm/providers/openai_responses/chat_extension'
require_relative 'ruby_llm/providers/openai_responses/model_registry'
require_relative 'ruby_llm/providers/openai_responses/active_record_extension'
require_relative 'ruby_llm/providers/openai_responses/web_socket'

# Include all modules in the provider class
require_relative 'ruby_llm/providers/openai_responses'

# Register the provider
RubyLLM::Provider.register :openai_responses, RubyLLM::Providers::OpenAIResponses

# Register models for this provider
RubyLLM::Providers::OpenAIResponses::ModelRegistry.register_all!

# Extend RubyLLM module with ResponsesAPI namespace
module RubyLLM
  # ResponsesAPI namespace for direct access to helpers and version
  module ResponsesAPI
    VERSION = '0.5.4'

    # Shorthand access to built-in tool helpers
    BuiltInTools = Providers::OpenAIResponses::BuiltInTools
    State = Providers::OpenAIResponses::State
    Background = Providers::OpenAIResponses::Background
    Compaction = Providers::OpenAIResponses::Compaction
    Containers = Providers::OpenAIResponses::Containers
    Batches = Providers::OpenAIResponses::Batches
    Batch = Providers::OpenAIResponses::Batch
    WebSocket = Providers::OpenAIResponses::WebSocket
  end

  # Create a new Batch for bulk request processing
  def self.batch(...)
    Providers::OpenAIResponses::Batch.new(...)
  end

  # List existing batches
  def self.batches(provider: :openai_responses, **kwargs)
    slug = provider.to_sym
    provider_class = Provider.providers[slug]
    raise Error.new(nil, "Unknown provider: #{slug}") unless provider_class

    provider_class.new(config).list_batches(**kwargs)
  end
end
