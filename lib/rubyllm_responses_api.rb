# frozen_string_literal: true

require 'ruby_llm'

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
require_relative 'ruby_llm/providers/openai_responses/message_extension'

# Provider class
require_relative 'ruby_llm/providers/openai_responses'

# Register the provider
RubyLLM::Provider.register :openai_responses, RubyLLM::Providers::OpenAIResponses

# Convenience module for direct access to helpers
module RubyLLMResponsesAPI
  VERSION = '0.1.0'

  # Shorthand access to built-in tool helpers
  BuiltInTools = RubyLLM::Providers::OpenAIResponses::BuiltInTools
  State = RubyLLM::Providers::OpenAIResponses::State
  Background = RubyLLM::Providers::OpenAIResponses::Background
end
