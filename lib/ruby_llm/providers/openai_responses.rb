# frozen_string_literal: true

module RubyLLM
  module Providers
    # OpenAI Responses API provider for RubyLLM.
    # Implements the new Responses API which provides built-in tools,
    # stateful conversations, background mode, and MCP support.
    class OpenAIResponses < Provider
      include OpenAIResponses::Chat
      include OpenAIResponses::Streaming
      include OpenAIResponses::Tools
      include OpenAIResponses::Models
      include OpenAIResponses::Media

      def api_base
        @config.openai_api_base || 'https://api.openai.com/v1'
      end

      def headers
        {
          'Authorization' => "Bearer #{@config.openai_api_key}",
          'OpenAI-Organization' => @config.openai_organization_id,
          'OpenAI-Project' => @config.openai_project_id
        }.compact
      end

      # Retrieve a stored response by ID
      # @param response_id [String] The response ID to retrieve
      # @return [Hash] The response data
      def retrieve_response(response_id)
        response = @connection.get(Background.retrieve_url(response_id))
        response.body
      end

      # Cancel a background response
      # @param response_id [String] The response ID to cancel
      # @return [Hash] The cancellation result
      def cancel_response(response_id)
        response = @connection.post(Background.cancel_url(response_id), {})
        response.body
      end

      # Delete a stored response
      # @param response_id [String] The response ID to delete
      # @return [Hash] The deletion result
      def delete_response(response_id)
        response = @connection.delete(Background.retrieve_url(response_id))
        response.body
      end

      # List input items for a response
      # @param response_id [String] The response ID
      # @return [Hash] The input items
      def list_input_items(response_id)
        response = @connection.get(Background.input_items_url(response_id))
        response.body
      end

      # Poll a background response until completion
      # @param response_id [String] The response ID to poll
      # @param interval [Float] Polling interval in seconds
      # @param timeout [Float, nil] Maximum time to wait in seconds
      # @yield [Hash] Called with response data on each poll
      # @return [Hash] The final response data
      def poll_response(response_id, interval: 1.0, timeout: nil)
        start_time = Time.now
        loop do
          response_data = retrieve_response(response_id)
          yield response_data if block_given?

          return response_data if Background.complete?(response_data)

          if timeout && (Time.now - start_time) > timeout
            raise Error, "Polling timeout after #{timeout} seconds"
          end

          sleep interval
        end
      end

      class << self
        def capabilities
          OpenAIResponses::Capabilities
        end

        def configuration_requirements
          %i[openai_api_key]
        end

        def slug
          :openai_responses
        end
      end
    end
  end
end
