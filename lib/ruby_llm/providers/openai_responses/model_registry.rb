# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Registers OpenAI Responses API models with RubyLLM
      module ModelRegistry
        MODELS = [
          # GPT-4o series
          {
            id: 'gpt-4o',
            name: 'GPT-4o',
            provider: 'openai_responses',
            family: 'gpt-4o',
            context_window: 128_000,
            max_output_tokens: 16_384,
            modalities: { input: %w[text image], output: ['text'] },
            capabilities: %w[streaming function_calling structured_output vision web_search code_interpreter]
          },
          {
            id: 'gpt-4o-mini',
            name: 'GPT-4o Mini',
            provider: 'openai_responses',
            family: 'gpt-4o-mini',
            context_window: 128_000,
            max_output_tokens: 16_384,
            modalities: { input: %w[text image], output: ['text'] },
            capabilities: %w[streaming function_calling structured_output vision web_search code_interpreter]
          },
          # GPT-4.1 series
          {
            id: 'gpt-4.1',
            name: 'GPT-4.1',
            provider: 'openai_responses',
            family: 'gpt-4.1',
            context_window: 1_000_000,
            max_output_tokens: 32_768,
            modalities: { input: %w[text image], output: ['text'] },
            capabilities: %w[streaming function_calling structured_output vision web_search code_interpreter]
          },
          {
            id: 'gpt-4.1-mini',
            name: 'GPT-4.1 Mini',
            provider: 'openai_responses',
            family: 'gpt-4.1',
            context_window: 1_000_000,
            max_output_tokens: 32_768,
            modalities: { input: %w[text image], output: ['text'] },
            capabilities: %w[streaming function_calling structured_output vision web_search code_interpreter]
          },
          {
            id: 'gpt-4.1-nano',
            name: 'GPT-4.1 Nano',
            provider: 'openai_responses',
            family: 'gpt-4.1',
            context_window: 1_000_000,
            max_output_tokens: 32_768,
            modalities: { input: %w[text image], output: ['text'] },
            capabilities: %w[streaming function_calling structured_output vision web_search code_interpreter]
          },
          # O-series reasoning models
          {
            id: 'o1',
            name: 'O1',
            provider: 'openai_responses',
            family: 'o1',
            context_window: 200_000,
            max_output_tokens: 100_000,
            modalities: { input: %w[text image], output: ['text'] },
            capabilities: %w[streaming function_calling structured_output vision reasoning]
          },
          {
            id: 'o1-mini',
            name: 'O1 Mini',
            provider: 'openai_responses',
            family: 'o1',
            context_window: 128_000,
            max_output_tokens: 65_536,
            modalities: { input: ['text'], output: ['text'] },
            capabilities: %w[streaming function_calling structured_output reasoning]
          },
          {
            id: 'o3',
            name: 'O3',
            provider: 'openai_responses',
            family: 'o3',
            context_window: 200_000,
            max_output_tokens: 100_000,
            modalities: { input: %w[text image], output: ['text'] },
            capabilities: %w[streaming function_calling structured_output vision reasoning web_search code_interpreter]
          },
          {
            id: 'o3-mini',
            name: 'O3 Mini',
            provider: 'openai_responses',
            family: 'o3',
            context_window: 200_000,
            max_output_tokens: 100_000,
            modalities: { input: ['text'], output: ['text'] },
            capabilities: %w[streaming function_calling structured_output reasoning]
          },
          {
            id: 'o4-mini',
            name: 'O4 Mini',
            provider: 'openai_responses',
            family: 'o4',
            context_window: 200_000,
            max_output_tokens: 100_000,
            modalities: { input: ['text'], output: ['text'] },
            capabilities: %w[streaming function_calling structured_output reasoning web_search code_interpreter]
          }
        ].freeze

        module_function

        def register_all!
          MODELS.each do |model_data|
            model = RubyLLM::Model::Info.new(model_data)
            existing = RubyLLM::Models.instance.all.find { |m| m.id == model.id && m.provider == model.provider }
            RubyLLM::Models.instance.all << model unless existing
          end
        end
      end
    end
  end
end
