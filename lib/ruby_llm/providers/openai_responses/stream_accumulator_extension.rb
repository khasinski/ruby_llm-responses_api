# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Extends RubyLLM::StreamAccumulator to carry built_in_tool_events and
      # response_id from chunks through to the final assembled Message.
      # Without this the accumulator drops everything off the Chunk it does
      # not know about — including response_id, which breaks
      # previous_response_id chaining on the next turn for any streamed chat.
      module StreamAccumulatorExtension
        def add(chunk)
          super
          @response_id = chunk.response_id if chunk.respond_to?(:response_id) && chunk.response_id

          events = chunk_built_in_events(chunk)
          return if events.nil? || events.empty?

          @built_in_tool_events ||= []
          @built_in_tool_events.concat(events)
        end

        def to_message(response)
          message = super
          if @built_in_tool_events && !@built_in_tool_events.empty? && message.respond_to?(:built_in_tool_events=)
            message.built_in_tool_events = @built_in_tool_events
          end
          message.response_id = @response_id if @response_id && message.respond_to?(:response_id=)
          message
        end

        private

        def chunk_built_in_events(chunk)
          return nil unless chunk.respond_to?(:built_in_tool_events)

          chunk.built_in_tool_events
        end
      end
    end
  end
end

RubyLLM::StreamAccumulator.prepend(RubyLLM::Providers::OpenAIResponses::StreamAccumulatorExtension)
