# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Extra state carried by this provider; native Message fields are preserved.
      module MessageExtension
        attr_accessor :response_id, :built_in_tool_events, :responses_api_body

        def initialize(options = {})
          super
          @response_id = options[:response_id]
          @built_in_tool_events = options[:built_in_tool_events]
          @responses_api_body = options[:responses_api_body]
        end

        def to_h
          response_id ? super.merge(response_id: response_id) : super
        end
      end
    end
  end
end

RubyLLM::Message.prepend(RubyLLM::Providers::OpenAIResponses::MessageExtension)
