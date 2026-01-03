# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Statefulness support for the OpenAI Responses API.
      # Handles conversation state via previous_response_id and store options.
      module State
        module_function

        # Add state parameters to payload
        # @param payload [Hash] The request payload
        # @param params [Hash] Additional parameters that may contain state options
        # @return [Hash] Updated payload with state parameters
        def apply_state_params(payload, params)
          # Handle previous_response_id for conversation chaining
          if params[:previous_response_id]
            payload[:previous_response_id] = params[:previous_response_id]
          end

          # Handle store option (defaults to true in Responses API)
          payload[:store] = params[:store] if params.key?(:store)

          # Handle metadata
          payload[:metadata] = params[:metadata] if params[:metadata]

          payload
        end

        # Extract response ID from a completed response for chaining
        # @param response [Hash] The API response
        # @return [String, nil] The response ID
        def extract_response_id(response)
          response['id']
        end

        # Check if a response was stored
        # @param response [Hash] The API response
        # @return [Boolean]
        def response_stored?(response)
          # Responses are stored by default unless store: false was set
          response['store'] != false
        end

        # Build parameters for continuing a conversation
        # @param previous_response_id [String] The ID of the previous response
        # @param store [Boolean] Whether to store this response (default: true)
        # @return [Hash] Parameters to pass to the next request
        def continuation_params(previous_response_id, store: true)
          {
            previous_response_id: previous_response_id,
            store: store
          }
        end
      end
    end
  end
end
