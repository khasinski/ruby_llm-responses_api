# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Extends RubyLLM::Message to support response_id for stateful conversations
      # and built_in_tool_events for server-side tool calls (web_search,
      # code_interpreter, etc.) that should fire on_tool_call/on_tool_result.
      module MessageExtension
        attr_accessor :response_id, :built_in_tool_events

        def self.included(base)
          base.class_eval do
            alias_method :original_initialize, :initialize

            define_method(:initialize) do |options = {}|
              original_initialize(options)
              @response_id = options[:response_id]
              @built_in_tool_events = options[:built_in_tool_events]
            end

            alias_method :original_to_h, :to_h

            define_method(:to_h) do
              original_to_h.merge(response_id: response_id).compact
            end
          end
        end
      end
    end
  end
end

# Apply the extension to RubyLLM::Message
RubyLLM::Message.include(RubyLLM::Providers::OpenAIResponses::MessageExtension)
