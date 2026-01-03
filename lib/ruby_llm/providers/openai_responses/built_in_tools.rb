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
        def web_search(search_context_size: nil, user_location: nil)
          tool = { type: 'web_search_preview' }
          tool[:search_context_size] = search_context_size if search_context_size
          tool[:user_location] = user_location if user_location
          tool
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
