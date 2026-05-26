# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Server-side compaction support for long-running agent sessions.
      # Automatically compacts conversation context when token count exceeds threshold.
      module Compaction
        module_function

        # Build context_management parameter for compaction
        # @param compact_threshold [Integer] Token count threshold to trigger compaction (minimum 1000)
        # @return [Hash] Parameters to merge into request payload via with_params
        def compaction_params(compact_threshold: 200_000)
          {
            context_management: [
              { type: 'compaction', compact_threshold: compact_threshold }
            ]
          }
        end

        # Apply compaction settings to payload
        # @param payload [Hash] The request payload
        # @param params [Hash] Additional parameters that may contain compaction options
        # @return [Hash] Updated payload with context_management
        def apply_compaction(payload, params)
          if params[:compact_threshold]
            payload[:context_management] = [
              { type: 'compaction', compact_threshold: params[:compact_threshold] }
            ]
          elsif params[:context_management]
            payload[:context_management] = params[:context_management]
          end

          payload
        end

        # URL for explicit Responses API compaction.
        # @return [String] The URL path
        def compact_url
          'responses/compact'
        end

        # URL for Responses API input token counting.
        # @return [String] The URL path
        def input_tokens_url
          'responses/input_tokens'
        end
      end
    end
  end
end
