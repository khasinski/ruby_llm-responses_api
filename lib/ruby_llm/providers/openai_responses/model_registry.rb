# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Reuse the current OpenAI catalog rather than maintaining model snapshots.
      module ModelRegistry
        def by_provider(provider)
          own = super
          return own unless provider.to_s == 'openai_responses'

          native = super(:openai).all_including_unlisted.map do |source|
            RubyLLM::Model.new(source.to_h.merge(provider: 'openai_responses'))
          end
          self.class.new((own.all_including_unlisted + native).uniq(&:id))
        end

        def find(model_id, provider: nil, config: nil)
          super
        rescue RubyLLM::ModelNotFoundError
          raise unless provider.to_s == 'openai_responses'

          source = super(model_id, provider: :openai, config: config)
          RubyLLM::Model.new(source.to_h.merge(provider: 'openai_responses'))
        end
      end
    end
  end
end

RubyLLM::Models.prepend(RubyLLM::Providers::OpenAIResponses::ModelRegistry)
