# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Tools/function calling methods for the OpenAI Responses API.
      # Handles both custom function tools and built-in tools.
      module Tools
        module_function

        EMPTY_PARAMETERS_SCHEMA = {
          'type' => 'object',
          'properties' => {},
          'required' => [],
          'additionalProperties' => false
        }.freeze

        # Built-in tool type constants
        BUILT_IN_TOOLS = {
          web_search: { type: 'web_search_preview' },
          file_search: ->(vector_store_ids) { { type: 'file_search', vector_store_ids: vector_store_ids } },
          code_interpreter: { type: 'code_interpreter', container: { type: 'auto' } },
          image_generation: { type: 'image_generation' },
          computer_use: ->(opts) { { type: 'computer_use_preview', **opts } }
        }.freeze

        def tool_for(tool)
          # Check if it's a built-in tool specification
          return tool if tool.is_a?(Hash) && tool[:type]

          # Handle symbol references to built-in tools
          if tool.is_a?(Symbol) && BUILT_IN_TOOLS.key?(tool)
            built_in = BUILT_IN_TOOLS[tool]
            return built_in.is_a?(Proc) ? built_in.call([]) : built_in
          end

          # Standard function tool
          parameters_schema = parameters_schema_for(tool)

          definition = {
            type: 'function',
            name: tool.name,
            description: tool.description,
            parameters: parameters_schema
          }

          # Add strict mode if schema supports it
          definition[:strict] = true if parameters_schema['additionalProperties'] == false

          return definition if tool.respond_to?(:provider_params) && tool.provider_params.empty?

          if tool.respond_to?(:provider_params) && tool.provider_params.any?
            RubyLLM::Utils.deep_merge(definition, tool.provider_params)
          else
            definition
          end
        end

        def parameters_schema_for(tool)
          if tool.respond_to?(:params_schema) && tool.params_schema
            tool.params_schema
          elsif tool.respond_to?(:parameters)
            schema_from_parameters(tool.parameters)
          else
            EMPTY_PARAMETERS_SCHEMA
          end
        end

        def schema_from_parameters(parameters)
          return EMPTY_PARAMETERS_SCHEMA if parameters.nil? || parameters.empty?

          if defined?(RubyLLM::Tool::SchemaDefinition)
            schema_definition = RubyLLM::Tool::SchemaDefinition.from_parameters(parameters)
            schema_definition&.json_schema || EMPTY_PARAMETERS_SCHEMA
          else
            # Fallback for older RubyLLM versions
            build_schema_from_parameters(parameters)
          end
        end

        def build_schema_from_parameters(parameters)
          properties = {}
          required = []

          parameters.each do |name, param|
            properties[name.to_s] = {
              type: param.type || 'string',
              description: param.description
            }.compact

            required << name.to_s if param.required
          end

          {
            'type' => 'object',
            'properties' => properties,
            'required' => required,
            'additionalProperties' => false
          }
        end

        def format_tool_calls(tool_calls)
          return nil unless tool_calls&.any?

          tool_calls.map do |_, tc|
            {
              type: 'function_call',
              call_id: tc.id,
              name: tc.name,
              arguments: tc.arguments.is_a?(String) ? tc.arguments : JSON.generate(tc.arguments)
            }
          end
        end

        def parse_tool_calls(tool_calls, parse_arguments: true)
          return nil unless tool_calls&.any?

          tool_calls.to_h do |tc|
            call_id = tc['call_id'] || tc['id']
            [
              call_id,
              ToolCall.new(
                id: call_id,
                name: tc['name'],
                arguments: if parse_arguments
                             parse_tool_call_arguments(tc)
                           else
                             tc['arguments']
                           end
              )
            ]
          end
        end

        def parse_tool_call_arguments(tool_call)
          arguments = tool_call['arguments']

          if arguments.nil? || arguments.empty?
            {}
          elsif arguments.is_a?(Hash)
            arguments
          else
            JSON.parse(arguments)
          end
        rescue JSON::ParserError
          { raw: arguments }
        end

        # Helper to create built-in tool configurations
        def web_search_tool(search_context_size: nil)
          tool = { type: 'web_search_preview' }
          tool[:search_context_size] = search_context_size if search_context_size
          tool
        end

        def file_search_tool(vector_store_ids:, max_num_results: nil, ranking_options: nil)
          tool = {
            type: 'file_search',
            vector_store_ids: Array(vector_store_ids)
          }
          tool[:max_num_results] = max_num_results if max_num_results
          tool[:ranking_options] = ranking_options if ranking_options
          tool
        end

        def code_interpreter_tool(container_type: 'auto')
          {
            type: 'code_interpreter',
            container: { type: container_type }
          }
        end

        def image_generation_tool(partial_images: nil)
          tool = { type: 'image_generation' }
          tool[:partial_images] = partial_images if partial_images
          tool
        end

        def mcp_tool(server_label:, server_url:, require_approval: 'never', allowed_tools: nil, headers: nil)
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
      end
    end
  end
end
