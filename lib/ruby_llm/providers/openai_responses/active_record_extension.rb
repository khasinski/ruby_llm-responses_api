# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Keep native persistence for tools, usage, attachments and reasoning.
      module MessageMethodsExtension
        def to_llm
          message = super
          message.response_id = self[:response_id] if has_attribute?(:response_id)
          message
        end
      end

      module ChatMethodsExtension
        private

        def message_attributes(message)
          attributes = super
          assign_supported_attribute(attributes, :response_id, message.response_id)
          attributes
        end
      end

      def self.apply_active_record_extensions!
        require 'ruby_llm/active_record/message_methods'
        require 'ruby_llm/active_record/chat_methods'

        RubyLLM::ActiveRecord::MessageMethods.prepend(MessageMethodsExtension)
        RubyLLM::ActiveRecord::ChatMethods.prepend(ChatMethodsExtension)
      end
    end
  end
end

if defined?(ActiveSupport.on_load)
  ActiveSupport.on_load(:active_record) do
    RubyLLM::Providers::OpenAIResponses.apply_active_record_extensions!
  end
end
