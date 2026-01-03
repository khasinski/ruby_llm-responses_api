# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Extends RubyLLM's ActiveRecord MessageMethods to support response_id persistence
      # for stateful conversations with the OpenAI Responses API.
      #
      # Usage:
      #   1. Add a migration: add_column :messages, :response_id, :string
      #   2. This extension automatically includes response_id in to_llm conversion
      #   3. response_id is automatically saved when messages are persisted
      #
      module MessageMethodsExtension
        # Override to_llm to include response_id for Responses API support
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

      # Extends RubyLLM's ActiveRecord ChatMethods to persist response_id
      module ChatMethodsExtension
        # Override persist_message_completion to also save response_id
        def persist_message_completion(message)
          super

          # After the parent saves, update response_id if the column exists and message has one
          return unless message
          return unless message.respond_to?(:response_id) && message.response_id
          return unless @message.has_attribute?(:response_id)

          @message.update_column(:response_id, message.response_id)
        end
      end
    end
  end
end

# Extensions are applied when the user explicitly calls apply_active_record_extensions!
# This avoids loading ActiveSupport/ActiveRecord when not needed.
#
# Usage in Rails initializer (config/initializers/ruby_llm.rb):
#
#   RubyLLM::Providers::OpenAIResponses.apply_active_record_extensions!
#
module RubyLLM
  module Providers
    class OpenAIResponses
      @active_record_extensions_applied = false

      # Apply ActiveRecord extensions for response_id persistence.
      # Call this in a Rails initializer after ActiveRecord is loaded.
      #
      # @example
      #   # config/initializers/ruby_llm.rb
      #   RubyLLM::Providers::OpenAIResponses.apply_active_record_extensions!
      #
      def self.apply_active_record_extensions!
        return if @active_record_extensions_applied

        require 'ruby_llm/active_record/message_methods'
        require 'ruby_llm/active_record/chat_methods'

        RubyLLM::ActiveRecord::MessageMethods.prepend(MessageMethodsExtension)
        RubyLLM::ActiveRecord::ChatMethods.prepend(ChatMethodsExtension)

        @active_record_extensions_applied = true
      rescue LoadError, NameError => e
        warn "[ruby_llm-responses_api] Could not apply ActiveRecord extensions: #{e.message}"
      end
    end
  end
end
