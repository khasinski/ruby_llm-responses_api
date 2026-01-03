# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Model capabilities for OpenAI Responses API models.
      # Defines which models support which features.
      module Capabilities
        module_function

        # Models that support the Responses API
        RESPONSES_API_MODELS = %w[
          gpt-4o gpt-4o-mini gpt-4o-2024-05-13 gpt-4o-2024-08-06 gpt-4o-2024-11-20
          gpt-4o-mini-2024-07-18
          gpt-4.1 gpt-4.1-mini gpt-4.1-nano
          gpt-4-turbo gpt-4-turbo-2024-04-09 gpt-4-turbo-preview
          o1 o1-mini o1-preview o1-2024-12-17
          o3 o3-mini o4-mini
          chatgpt-4o-latest
        ].freeze

        # Models with vision capabilities
        VISION_MODELS = %w[
          gpt-4o gpt-4o-mini gpt-4o-2024-05-13 gpt-4o-2024-08-06 gpt-4o-2024-11-20
          gpt-4o-mini-2024-07-18
          gpt-4.1 gpt-4.1-mini gpt-4.1-nano
          gpt-4-turbo gpt-4-turbo-2024-04-09
          o1 o3 o4-mini
          chatgpt-4o-latest
        ].freeze

        # Reasoning models (o-series)
        REASONING_MODELS = %w[o1 o1-mini o1-preview o1-2024-12-17 o3 o3-mini o4-mini].freeze

        # Models that support web search
        WEB_SEARCH_MODELS = %w[
          gpt-4o gpt-4o-mini gpt-4.1 gpt-4.1-mini gpt-4.1-nano
          o1 o3 o3-mini o4-mini
        ].freeze

        # Models that support code interpreter
        CODE_INTERPRETER_MODELS = %w[
          gpt-4o gpt-4o-mini gpt-4.1 gpt-4.1-mini gpt-4.1-nano
          o1 o3 o3-mini o4-mini
        ].freeze

        # Context windows by model
        CONTEXT_WINDOWS = {
          'gpt-4o' => 128_000,
          'gpt-4o-mini' => 128_000,
          'gpt-4o-2024-05-13' => 128_000,
          'gpt-4o-2024-08-06' => 128_000,
          'gpt-4o-2024-11-20' => 128_000,
          'gpt-4o-mini-2024-07-18' => 128_000,
          'gpt-4.1' => 1_000_000,
          'gpt-4.1-mini' => 1_000_000,
          'gpt-4.1-nano' => 1_000_000,
          'gpt-4-turbo' => 128_000,
          'gpt-4-turbo-2024-04-09' => 128_000,
          'o1' => 200_000,
          'o1-mini' => 128_000,
          'o1-preview' => 128_000,
          'o3' => 200_000,
          'o3-mini' => 200_000,
          'o4-mini' => 200_000
        }.freeze

        # Max output tokens by model
        MAX_OUTPUT_TOKENS = {
          'gpt-4o' => 16_384,
          'gpt-4o-mini' => 16_384,
          'gpt-4o-2024-05-13' => 4_096,
          'gpt-4o-2024-08-06' => 16_384,
          'gpt-4o-2024-11-20' => 16_384,
          'gpt-4o-mini-2024-07-18' => 16_384,
          'gpt-4.1' => 32_768,
          'gpt-4.1-mini' => 32_768,
          'gpt-4.1-nano' => 32_768,
          'gpt-4-turbo' => 4_096,
          'o1' => 100_000,
          'o1-mini' => 65_536,
          'o3' => 100_000,
          'o3-mini' => 100_000,
          'o4-mini' => 100_000
        }.freeze

        # Pricing per million tokens (as of late 2024)
        PRICING = {
          'gpt-4o' => { input: 2.50, output: 10.00, cached_input: 1.25 },
          'gpt-4o-mini' => { input: 0.15, output: 0.60, cached_input: 0.075 },
          'gpt-4.1' => { input: 2.00, output: 8.00, cached_input: 0.50 },
          'gpt-4.1-mini' => { input: 0.40, output: 1.60, cached_input: 0.10 },
          'gpt-4.1-nano' => { input: 0.10, output: 0.40, cached_input: 0.025 },
          'o1' => { input: 15.00, output: 60.00, cached_input: 7.50 },
          'o1-mini' => { input: 1.10, output: 4.40, cached_input: 0.55 },
          'o3' => { input: 10.00, output: 40.00, cached_input: 2.50 },
          'o3-mini' => { input: 1.10, output: 4.40, cached_input: 0.275 },
          'o4-mini' => { input: 1.10, output: 4.40, cached_input: 0.275 }
        }.freeze

        def supports_responses_api?(model_id)
          model_matches?(model_id, RESPONSES_API_MODELS)
        end

        def supports_vision?(model_id)
          model_matches?(model_id, VISION_MODELS)
        end

        def supports_functions?(model_id)
          supports_responses_api?(model_id)
        end

        def supports_structured_output?(model_id)
          supports_responses_api?(model_id)
        end

        def supports_web_search?(model_id)
          model_matches?(model_id, WEB_SEARCH_MODELS)
        end

        def supports_code_interpreter?(model_id)
          model_matches?(model_id, CODE_INTERPRETER_MODELS)
        end

        def reasoning_model?(model_id)
          model_matches?(model_id, REASONING_MODELS)
        end

        def context_window_for(model_id)
          find_capability(model_id, CONTEXT_WINDOWS) || 128_000
        end

        def max_tokens_for(model_id)
          find_capability(model_id, MAX_OUTPUT_TOKENS) || 16_384
        end

        def input_price_for(model_id)
          pricing = find_capability(model_id, PRICING)
          pricing ? pricing[:input] : 0.0
        end

        def output_price_for(model_id)
          pricing = find_capability(model_id, PRICING)
          pricing ? pricing[:output] : 0.0
        end

        def pricing_for(model_id)
          pricing = find_capability(model_id, PRICING) || { input: 0.0, output: 0.0 }
          {
            text_tokens: {
              standard: {
                input_per_million: pricing[:input],
                output_per_million: pricing[:output],
                cached_input_per_million: pricing[:cached_input] || (pricing[:input] / 2)
              }
            }
          }
        end

        def modalities_for(model_id)
          input = ['text']
          input << 'image' if supports_vision?(model_id)

          {
            input: input,
            output: ['text']
          }
        end

        def capabilities_for(model_id)
          caps = %w[streaming function_calling structured_output]
          caps << 'vision' if supports_vision?(model_id)
          caps << 'web_search' if supports_web_search?(model_id)
          caps << 'code_interpreter' if supports_code_interpreter?(model_id)
          caps << 'reasoning' if reasoning_model?(model_id)
          caps
        end

        def model_family(model_id)
          case model_id
          when /^gpt-4\.1/ then 'gpt-4.1'
          when /^gpt-4o-mini/ then 'gpt-4o-mini'
          when /^gpt-4o/ then 'gpt-4o'
          when /^gpt-4-turbo/ then 'gpt-4-turbo'
          when /^o1/ then 'o1'
          when /^o3/ then 'o3'
          when /^o4/ then 'o4'
          else 'other'
          end
        end

        def format_display_name(model_id)
          model_id
            .gsub(/[-_]/, ' ')
            .split
            .map(&:capitalize)
            .join(' ')
        end

        # Temperature is not supported for reasoning models
        def normalize_temperature(temperature, model_id)
          return nil if reasoning_model?(model_id)

          temperature
        end

        private_class_method def find_capability(model_id, mapping)
          # Direct match
          return mapping[model_id] if mapping.key?(model_id)

          # Try base model name (without date suffix)
          base_model = model_id.gsub(/-\d{4}-\d{2}-\d{2}$/, '')
          return mapping[base_model] if mapping.key?(base_model)

          nil
        end

        private_class_method def model_matches?(model_id, model_list)
          model_list.any? do |pattern|
            model_id == pattern || model_id.start_with?("#{pattern}-")
          end
        end
      end
    end
  end
end
