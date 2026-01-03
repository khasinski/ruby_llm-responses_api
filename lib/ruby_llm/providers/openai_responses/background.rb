# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Background mode support for the OpenAI Responses API.
      # Handles async responses with polling for long-running tasks.
      module Background
        module_function

        # Status constants
        QUEUED = 'queued'
        IN_PROGRESS = 'in_progress'
        COMPLETED = 'completed'
        FAILED = 'failed'
        CANCELLED = 'cancelled'
        INCOMPLETE = 'incomplete'

        TERMINAL_STATUSES = [COMPLETED, FAILED, CANCELLED, INCOMPLETE].freeze
        PENDING_STATUSES = [QUEUED, IN_PROGRESS].freeze

        # Add background mode to payload
        # @param payload [Hash] The request payload
        # @param background [Boolean] Whether to run in background mode
        # @return [Hash] Updated payload
        def apply_background_mode(payload, background: false)
          payload[:background] = background if background
          payload
        end

        # Check if response is still pending
        # @param response [Hash] The API response
        # @return [Boolean]
        def pending?(response)
          status = response['status']
          PENDING_STATUSES.include?(status)
        end

        # Check if response is complete (terminal state)
        # @param response [Hash] The API response
        # @return [Boolean]
        def complete?(response)
          status = response['status']
          TERMINAL_STATUSES.include?(status)
        end

        # Check if response was successful
        # @param response [Hash] The API response
        # @return [Boolean]
        def successful?(response)
          response['status'] == COMPLETED
        end

        # Check if response failed
        # @param response [Hash] The API response
        # @return [Boolean]
        def failed?(response)
          response['status'] == FAILED
        end

        # Get response status
        # @param response [Hash] The API response
        # @return [String] The status
        def status(response)
          response['status']
        end

        # Get error information if failed
        # @param response [Hash] The API response
        # @return [Hash, nil] Error information
        def error_info(response)
          response['error']
        end

        # URL to retrieve a response by ID
        # @param response_id [String] The response ID
        # @return [String] The URL path
        def retrieve_url(response_id)
          "responses/#{response_id}"
        end

        # URL to cancel a response
        # @param response_id [String] The response ID
        # @return [String] The URL path
        def cancel_url(response_id)
          "responses/#{response_id}/cancel"
        end

        # URL to list input items for a response
        # @param response_id [String] The response ID
        # @return [String] The URL path
        def input_items_url(response_id)
          "responses/#{response_id}/input_items"
        end
      end
    end
  end
end
