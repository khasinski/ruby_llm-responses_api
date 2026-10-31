# frozen_string_literal: true

module RubyLLM
  module Providers
    # OpenAI Responses API provider for RubyLLM.
    # Implements the new Responses API which provides built-in tools,
    # stateful conversations, background mode, and MCP support.
    class OpenAIResponses
      protocol :responses, OpenAIResponses::Protocol, batches: Protocols::Responses::Batches
      protocol :files, Protocols::OpenAI::Files

      def protocol_for(_model, **)
        protocols.fetch(:responses)
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
        response = delete_request(Background.retrieve_url(response_id))
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

          raise Error, "Polling timeout after #{timeout} seconds" if timeout && (Time.now - start_time) > timeout

          sleep interval
        end
      end

      # Run an explicit compaction pass over a response input.
      # @param model [String] Model ID used for compaction
      # @param input [String, Array<Hash>] Response input items to compact
      # @param params [Hash] Additional Responses API parameters
      # @return [Hash] Compacted response data
      def compact_response(model:, input:, **params)
        response = @connection.post(Compaction.compact_url, { model: model, input: input }.merge(params))
        response.body
      end

      # Count input tokens for a Responses API request without creating a response.
      # @param model [String] Model ID used for tokenization
      # @param input [String, Array<Hash>] Response input
      # @param params [Hash] Additional Responses API parameters
      # @return [Hash] Token count data
      def count_input_tokens(model:, input:, **params)
        response = @connection.post(Compaction.input_tokens_url, { model: model, input: input }.merge(params))
        response.body
      end

      # --- Container Management ---

      # Create a new container
      # @param name [String, nil] Container name
      # @param expires_after [Hash, nil] Expiry configuration
      # @param file_ids [Array<String>, nil] File IDs to copy into container
      # @param memory_limit [String, nil] Memory limit: '1g', '4g', '16g', '64g'
      # @return [Hash] Created container data
      def create_container(name: nil, expires_after: nil, file_ids: nil, memory_limit: nil)
        payload = Containers.create_payload(
          name: name, expires_after: expires_after,
          file_ids: file_ids, memory_limit: memory_limit
        )
        response = @connection.post(Containers.containers_url, payload)
        response.body
      end

      # Retrieve a container by ID
      # @param container_id [String] The container ID
      # @return [Hash] Container data
      def retrieve_container(container_id)
        response = @connection.get(Containers.container_url(container_id))
        response.body
      end

      # Delete a container
      # @param container_id [String] The container ID
      # @return [Hash] Deletion result
      def delete_container(container_id)
        response = delete_request(Containers.container_url(container_id))
        response.body
      end

      # List files in a container
      # @param container_id [String] The container ID
      # @return [Hash] File listing
      def list_container_files(container_id)
        response = @connection.get(Containers.container_files_url(container_id))
        response.body
      end

      # Retrieve a specific file from a container
      # @param container_id [String] The container ID
      # @param file_id [String] The file ID
      # @return [Hash] File metadata
      def retrieve_container_file(container_id, file_id)
        response = @connection.get(Containers.container_file_url(container_id, file_id))
        response.body
      end

      # Get file content from a container
      # @param container_id [String] The container ID
      # @param file_id [String] The file ID
      # @return [String] File content
      def retrieve_container_file_content(container_id, file_id)
        response = @connection.get(Containers.container_file_content_url(container_id, file_id))
        response.body
      end

      # --- Batch API ---

      # List batches
      # @param limit [Integer] Number of batches to return (default: 20)
      # @param after [String, nil] Cursor for pagination
      # @return [Hash] Batch listing with 'data' array
      def list_batches(limit: 20, after: nil)
        url = Batches.batches_url
        params = { limit: limit }
        params[:after] = after if after
        response = @connection.get(url) do |req|
          req.params.merge!(params)
        end
        response.body
      end

      # Headers are part of the handshake, so a changed set uses a new connection.
      def responses_websocket(additional_headers = {})
        if @ws_connection && @ws_headers != additional_headers
          @ws_connection.disconnect
          @ws_connection = nil
        end
        @ws_headers = additional_headers.dup
        @ws_connection ||= WebSocket.new(
          api_key: @config.openai_api_key, api_base: api_base,
          organization_id: @config.openai_organization_id, project_id: @config.openai_project_id,
          headers: additional_headers
        )
        @ws_connection.connect unless @ws_connection.connected?
        @ws_connection
      end

      private

      def delete_request(url)
        @connection.delete(url)
      end

      class << self
        def configuration_options
          %i[
            openai_api_key
            openai_api_base
            openai_organization_id
            openai_project_id
          ]
        end

        def configuration_requirements
          %i[openai_api_key]
        end

        def models_dev_alias(model_id, models, provider_model = nil)
          source = models["openai:#{model_id}"] || super
          source && RubyLLM::Model.new(source.to_h.merge(provider: 'openai_responses'))
        end
      end
    end
  end
end
