# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Model listing methods for the OpenAI Responses API.
      module Models
        module_function

        def models_url
          'models'
        end

        def parse_list_models_response(response, slug, capabilities)
          models_data = response.body
          models_data = models_data['data'] if models_data.is_a?(Hash) && models_data['data']

          Array(models_data).filter_map do |model_data|
            model_id = model_data['id']

            # Only include models that support the Responses API
            next unless capabilities.supports_responses_api?(model_id)

            Model::Info.new(
              id: model_id,
              name: capabilities.format_display_name(model_id),
              provider: slug,
              family: capabilities.model_family(model_id),
              context_window: capabilities.context_window_for(model_id),
              max_output_tokens: capabilities.max_tokens_for(model_id),
              modalities: capabilities.modalities_for(model_id),
              capabilities: capabilities.capabilities_for(model_id),
              pricing: capabilities.pricing_for(model_id),
              metadata: {
                created_at: model_data['created'] ? Time.at(model_data['created']) : nil,
                owned_by: model_data['owned_by'],
                supports_responses_api: true,
                supports_web_search: capabilities.supports_web_search?(model_id),
                supports_code_interpreter: capabilities.supports_code_interpreter?(model_id),
                reasoning_model: capabilities.reasoning_model?(model_id)
              }.compact
            )
          end
        end
      end
    end
  end
end
