# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Extends RubyLLM's ActiveRecord MessageMethods to support response_id persistence
      # for stateful conversations with the OpenAI Responses API.
      #
      # This is automatically applied when Rails loads ActiveRecord.
      # Just add a migration: add_column :messages, :response_id, :string
      #

      # Extension for the NEW MessageMethods (RubyLLM 2.0+)
      module MessageMethodsExtension
        def to_llm
          cached = has_attribute?(:cached_tokens) ? self[:cached_tokens] : nil
          cache_creation = has_attribute?(:cache_creation_tokens) ? self[:cache_creation_tokens] : nil
          resp_id = has_attribute?(:response_id) ? self[:response_id] : nil

          RubyLLM::Message.new(
            role: role.to_sym,
            content: extract_content,
            tool_calls: extract_tool_calls,
            tool_call_id: extract_tool_call_id,
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            cached_tokens: cached,
            cache_creation_tokens: cache_creation,
            model_id: model_association&.model_id,
            response_id: resp_id
          )
        end
      end

      # Extension for the NEW ChatMethods (RubyLLM 2.0+)
      module ChatMethodsExtension
        def persist_message_completion(message)
          super
          save_response_id(message)
        end

        private

        def save_response_id(message)
          return unless message
          return unless message.respond_to?(:response_id) && message.response_id
          return unless @message.has_attribute?(:response_id)

          @message.update_column(:response_id, message.response_id)
        end
      end

      # Extension for LEGACY MessageLegacyMethods (RubyLLM 1.x)
      module MessageLegacyMethodsExtension
        def to_llm
          resp_id = has_attribute?(:response_id) ? self[:response_id] : nil

          RubyLLM::Message.new(
            role: role.to_sym,
            content: extract_content,
            tool_calls: extract_tool_calls,
            tool_call_id: extract_tool_call_id,
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            model_id: model_id,
            response_id: resp_id
          )
        end
      end

      # Extension for LEGACY ChatLegacyMethods (RubyLLM 1.x)
      module ChatLegacyMethodsExtension
        def persist_message_completion(message)
          super
          save_response_id_legacy(message)
        end

        private

        def save_response_id_legacy(message)
          return unless message
          return unless message.respond_to?(:response_id) && message.response_id
          return unless @message.has_attribute?(:response_id)

          @message.update_column(:response_id, message.response_id)
        end
      end

      @active_record_extensions_applied = false

      # Apply ActiveRecord extensions for response_id persistence.
      # Called automatically when ActiveRecord loads, or can be called manually.
      def self.apply_active_record_extensions!
        return if @active_record_extensions_applied

        applied = false

        # Try to apply to NEW modules (RubyLLM 2.0+)
        begin
          require 'ruby_llm/active_record/message_methods'
          require 'ruby_llm/active_record/chat_methods'

          RubyLLM::ActiveRecord::MessageMethods.prepend(MessageMethodsExtension)
          RubyLLM::ActiveRecord::ChatMethods.prepend(ChatMethodsExtension)
          applied = true
        rescue LoadError, NameError
          # New modules not available
        end

        # Try to apply to LEGACY modules (RubyLLM 1.x)
        begin
          require 'ruby_llm/active_record/acts_as_legacy'

          if defined?(RubyLLM::ActiveRecord::MessageLegacyMethods)
            RubyLLM::ActiveRecord::MessageLegacyMethods.prepend(MessageLegacyMethodsExtension)
          end

          if defined?(RubyLLM::ActiveRecord::ChatLegacyMethods)
            RubyLLM::ActiveRecord::ChatLegacyMethods.prepend(ChatLegacyMethodsExtension)
          end
          applied = true
        rescue LoadError, NameError
          # Legacy modules not available
        end

        @active_record_extensions_applied = applied
      end
    end
  end
end

# Auto-apply extensions when ActiveRecord is loaded in Rails
if defined?(ActiveSupport.on_load)
  ActiveSupport.on_load(:active_record) do
    RubyLLM::Providers::OpenAIResponses.apply_active_record_extensions!
  end
end
