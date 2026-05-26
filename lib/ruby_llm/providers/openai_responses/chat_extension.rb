# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Extends RubyLLM::Chat to fire on_tool_call / on_tool_result for built-in
      # server-side tools (web_search, code_interpreter, file_search, etc.)
      # carried on the assistant message. This lets users observe built-in tool
      # activity through the same callback API as locally executed function
      # tools (issue #1).
      module ChatExtension
        def add_message(message_or_attributes)
          message = super
          dispatch_built_in_tool_events(message) if dispatch_built_in_tool_events?(message)
          message
        end

        private

        def dispatch_built_in_tool_events?(message)
          message.respond_to?(:built_in_tool_events) &&
            message.built_in_tool_events &&
            !message.built_in_tool_events.empty?
        end

        def dispatch_built_in_tool_events(message)
          message.built_in_tool_events.each do |event|
            fire_callback(:before_tool_call, :tool_call, event[:tool_call])
            fire_callback(:after_tool_result, :tool_result, event[:result])
          end
        end

        # Mirrors RubyLLM::Chat#run_callbacks (private since 1.13): dispatches
        # through the new @callbacks array API if present, and always falls
        # back to the legacy @on hash so older ruby_llm versions still work.
        def fire_callback(new_name, legacy_name, *args)
          callbacks = instance_variable_defined?(:@callbacks) ? @callbacks : nil
          callbacks[new_name]&.each { |cb| cb.call(*args) } if callbacks
          @on[legacy_name]&.call(*args)
        end
      end
    end
  end
end

RubyLLM::Chat.prepend(RubyLLM::Providers::OpenAIResponses::ChatExtension)
