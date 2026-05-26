# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Built-in tools support for the OpenAI Responses API.
      # Provides configuration helpers and result parsing for:
      # - Web Search
      # - File Search
      # - Code Interpreter
      # - Image Generation
      # - MCP (Model Context Protocol)
      module BuiltInTools
        module_function

        # Web Search tool configuration
        # @param search_context_size [String, nil] 'low', 'medium', or 'high'
        # @param user_location [Hash, nil] { type: 'approximate', city: '...', country: '...' }
        # @param preview [Boolean] use the legacy preview tool type
        def web_search(search_context_size: nil, user_location: nil, preview: false)
          tool = { type: preview ? 'web_search_preview' : 'web_search' }
          tool[:search_context_size] = search_context_size if search_context_size
          tool[:user_location] = user_location if user_location
          tool
        end

        # Legacy Web Search preview tool configuration.
        def web_search_preview(search_context_size: nil, user_location: nil)
          web_search(search_context_size: search_context_size, user_location: user_location, preview: true)
        end

        # File Search tool configuration
        # @param vector_store_ids [Array<String>] IDs of vector stores to search
        # @param max_num_results [Integer, nil] Maximum results to return
        # @param ranking_options [Hash, nil] Ranking configuration
        def file_search(vector_store_ids:, max_num_results: nil, ranking_options: nil)
          tool = {
            type: 'file_search',
            vector_store_ids: Array(vector_store_ids)
          }
          tool[:max_num_results] = max_num_results if max_num_results
          tool[:ranking_options] = ranking_options if ranking_options
          tool
        end

        # Code Interpreter tool configuration
        # @param container_type [String] 'auto' or specific container type
        def code_interpreter(container_type: 'auto')
          {
            type: 'code_interpreter',
            container: { type: container_type }
          }
        end

        # Image Generation tool configuration
        # @param partial_images [Integer, nil] Number of partial images during streaming
        def image_generation(partial_images: nil)
          tool = { type: 'image_generation' }
          tool[:partial_images] = partial_images if partial_images
          tool
        end

        # MCP (Model Context Protocol) tool configuration
        # @param server_label [String] Label for the MCP server
        # @param server_url [String] URL of the MCP server
        # @param require_approval [String] 'never', 'always', or specific tool patterns
        # @param allowed_tools [Array<String>, nil] List of allowed tool names
        # @param headers [Hash, nil] Additional headers for the MCP server
        def mcp(server_label:, server_url:, require_approval: 'never', allowed_tools: nil, headers: nil)
          tool = {
            type: 'mcp',
            server_label: server_label,
            server_url: server_url,
            require_approval: require_approval
          }
          tool[:allowed_tools] = allowed_tools if allowed_tools
          tool[:headers] = headers if headers
          tool
        end

        # Computer Use tool configuration (preview)
        # @param display_width [Integer] Display width in pixels
        # @param display_height [Integer] Display height in pixels
        # @param environment [String] 'browser' or 'mac' or 'windows' or 'ubuntu'
        def computer_use(display_width:, display_height:, environment: 'browser')
          {
            type: 'computer_use_preview',
            display_width: display_width,
            display_height: display_height,
            environment: environment
          }
        end

        # Shell tool configuration
        # @param environment_type [String] 'container_auto', 'container_reference', or 'local'
        # @param container_id [String, nil] Container ID for 'container_reference' type
        # @param network_policy [Hash, nil] Network policy (e.g. { type: 'allowlist', allowed_domains: [...] })
        # @param memory_limit [String, nil] Memory limit: '1g', '4g', '16g', '64g'
        def shell(environment_type: 'container_auto', container_id: nil,
                  network_policy: nil, memory_limit: nil)
          env = if container_id
                  { type: 'container_reference', container_id: container_id }
                else
                  { type: environment_type }
                end

          env[:network_policy] = network_policy if network_policy
          env[:memory_limit] = memory_limit if memory_limit

          { type: 'shell', environment: env }
        end

        # Apply Patch tool configuration
        # Enables the model to create, update, and delete files using structured diffs.
        def apply_patch
          { type: 'apply_patch' }
        end

        # Parse web search results from output
        # @param output [Array] Response output array
        # @return [Array<Hash>] Parsed search results with citations
        def parse_web_search_results(output)
          output
            .select { |item| item['type'] == 'web_search_call' }
            .map do |item|
              {
                id: item['id'],
                status: item['status'],
                results: parse_citations(item)
              }
            end
        end

        # Parse file search results from output
        # @param output [Array] Response output array
        # @return [Array<Hash>] Parsed file search results
        def parse_file_search_results(output)
          output
            .select { |item| item['type'] == 'file_search_call' }
            .map do |item|
              {
                id: item['id'],
                status: item['status'],
                results: item['results'] || []
              }
            end
        end

        # Parse code interpreter results from output
        # @param output [Array] Response output array
        # @return [Array<Hash>] Parsed code interpreter results
        def parse_code_interpreter_results(output)
          output
            .select { |item| item['type'] == 'code_interpreter_call' }
            .map do |item|
              {
                id: item['id'],
                code: item['code'],
                results: item['results'] || [],
                container_id: item['container_id']
              }
            end
        end

        # Parse image generation results from output
        # @param output [Array] Response output array
        # @return [Array<Hash>] Parsed image generation results
        def parse_image_generation_results(output)
          output
            .select { |item| item['type'] == 'image_generation_call' }
            .map do |item|
              {
                id: item['id'],
                status: item['status'],
                result: item['result']
              }
            end
        end

        # Parse apply_patch call results from output
        # @param output [Array] Response output array
        # @return [Array<Hash>] Parsed apply_patch call results
        def parse_apply_patch_results(output)
          output
            .select { |item| item['type'] == 'apply_patch_call' }
            .map do |item|
              {
                id: item['id'],
                call_id: item['call_id'],
                status: item['status'],
                operation: item['operation']
              }
            end
        end

        # Server-executed built-in tool output item types and their argument
        # extractors. The key is the output `type` from the Responses API; the
        # value is a lambda that pulls the relevant arguments out of that item.
        # To support a new built-in tool, add an entry here.
        CALL_ARGUMENT_EXTRACTORS = {
          'web_search_call' => ->(item) { { action: item['action'], query: item.dig('action', 'query') } },
          'file_search_call' => ->(item) { { queries: item['queries'] } },
          'code_interpreter_call' => ->(item) { { code: item['code'], container_id: item['container_id'] } },
          'image_generation_call' => ->(_item) { {} },
          'shell_call' => ->(item) { { action: item['action'], container_id: item['container_id'] } },
          'local_shell_call' => ->(item) { { action: item['action'], container_id: item['container_id'] } },
          'apply_patch_call' => ->(item) { { operation: item['operation'] } },
          'mcp_call' => lambda { |item|
            { name: item['name'], arguments: item['arguments'], server_label: item['server_label'] }
          },
          'computer_call' => ->(item) { { action: item['action'] } }
        }.freeze

        # Build a list of {tool_call:, result:} events from the response output.
        # Used to surface server-side built-in tool activity through the standard
        # on_tool_call / on_tool_result callbacks (issue #1).
        def extract_events(output)
          return [] unless output.is_a?(Array)

          output.select { |item| CALL_ARGUMENT_EXTRACTORS.key?(item['type']) }
                .map { |item| build_event(item) }
        end

        private_class_method def build_event(item)
          type_label = item['type'].sub(/_call\z/, '')

          tool_call = RubyLLM::ToolCall.new(
            id: item['id'],
            name: type_label,
            arguments: call_arguments(item)
          )

          {
            tool_call: tool_call,
            result: call_result(item)
          }
        end

        private_class_method def call_arguments(item)
          extractor = CALL_ARGUMENT_EXTRACTORS[item['type']]
          return {} unless extractor

          extractor.call(item).compact
        end

        private_class_method def call_result(item)
          {
            id: item['id'],
            type: item['type'],
            status: item['status'],
            results: item['results'],
            result: item['result'],
            output: item['output'],
            action: item['action']
          }.compact
        end

        # Parse shell call results from output
        # @param output [Array] Response output array
        # @return [Array<Hash>] Parsed shell call results
        def parse_shell_call_results(output)
          output
            .select { |item| item['type'] == 'shell_call' }
            .map do |item|
              {
                id: item['id'],
                call_id: item['call_id'],
                status: item['status'],
                action: item['action'],
                container_id: item['container_id']
              }
            end
        end

        # Extract all citations from message content
        # @param content [Array] Message content array
        # @return [Array<Hash>] All citations/annotations
        def extract_citations(content)
          return [] unless content.is_a?(Array)

          content
            .select { |c| c['type'] == 'output_text' }
            .flat_map { |c| c['annotations'] || [] }
            .map do |annotation|
              {
                type: annotation['type'],
                text: annotation['text'],
                url: annotation['url'],
                title: annotation['title'],
                start_index: annotation['start_index'],
                end_index: annotation['end_index']
              }.compact
            end
        end

        private_class_method def parse_citations(item)
          return [] unless item['results']

          item['results'].map do |result|
            {
              url: result['url'],
              title: result['title'],
              snippet: result['snippet']
            }.compact
          end
        end
      end
    end
  end
end
