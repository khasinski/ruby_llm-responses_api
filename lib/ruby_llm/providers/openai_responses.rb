# frozen_string_literal: true

module RubyLLM
  module Providers
    # OpenAI Responses API provider for RubyLLM.
    # Implements the new Responses API which provides built-in tools,
    # stateful conversations, background mode, and MCP support.
    class OpenAIResponses
      include OpenAIResponses::Chat
      include OpenAIResponses::Streaming
      include OpenAIResponses::Tools
      include OpenAIResponses::Models
      include OpenAIResponses::Media

      def api_base
        @config.openai_api_base || 'https://api.openai.com/v1'
      end

      # Override to support WebSocket transport via with_params(transport: :websocket)
      # rubocop:disable Metrics/ParameterLists
      def complete(messages, tools:, temperature:, model:, params: {}, headers: {},
                   schema: nil, thinking: nil, tool_prefs: nil, &block)
        if params[:transport]&.to_sym == :websocket
          ws_complete(messages, tools: tools, temperature: temperature, model: model,
                                params: params.except(:transport), schema: schema,
                                thinking: thinking, &block)
        else
          super
        end
      end
      # rubocop:enable Metrics/ParameterLists

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

      private

      def ws_complete(messages, tools:, temperature:, model:, params:, schema:, thinking:, &block) # rubocop:disable Metrics/ParameterLists
        normalized_temperature = maybe_normalize_temperature(temperature, model)

        payload = Utils.deep_merge(
          render_payload(
            messages,
            tools: tools,
            temperature: normalized_temperature,
            model: model,
            stream: true,
            schema: schema,
            thinking: thinking
          ),
          params
        )

        ws_connection.connect unless ws_connection.connected?
        ws_connection.call(payload, &block)
      end

      def ws_connection
        @ws_connection ||= WebSocket.new(
          api_key: @config.openai_api_key,
          api_base: api_base,
          organization_id: @config.openai_organization_id,
          project_id: @config.openai_project_id
        )
      end

      # DELETE request via the underlying Faraday connection
      # RubyLLM::Connection only exposes get/post, so we use Faraday directly
      def delete_request(url)
        @connection.connection.delete(url) do |req|
          req.headers.merge!(headers)
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
          'openai_responses'
        end
      end
    end
  end
end
