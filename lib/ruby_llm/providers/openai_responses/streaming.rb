# frozen_string_literal: true

require 'delegate'

module RubyLLM
  module Providers
    class OpenAIResponses
      # Streaming methods for the OpenAI Responses API.
      # Handles SSE events with typed event format.
      module Streaming
        class StreamRawResponse < SimpleDelegator
          attr_reader :body

          def initialize(response, body)
            super(response)
            @body = body
          end
        end

        class CompletedResponseAccumulator
          def initialize
            @completed_response = nil
            @output_items_by_index = {}
            @shell_commands_by_output_index = Hash.new { |hash, key| hash[key] = {} }
            @shell_outputs_by_item_id = {}
            @shell_outputs_by_output_index = {}
          end

          def add(event)
            return unless event.is_a?(Hash)

            case event['type']
            when 'response.output_item.done'
              add_output_item(event)
            when 'response.shell_call_command.done'
              add_shell_command(event)
            when 'response.shell_call_output_content.done'
              add_shell_output_content(event)
            when 'response.completed'
              @completed_response = RubyLLM::Utils.deep_dup(event['response'] || {})
            end
          end

          def build_response(raw_response)
            body = build_body
            base_response = raw_response || build_default_response
            StreamRawResponse.new(base_response, body)
          end

          private

          def add_output_item(event)
            output_index = event['output_index']
            return if output_index.nil?

            item = RubyLLM::Utils.deep_dup(event['item'] || {})

            case item['type']
            when 'shell_call'
              merge_shell_commands!(item, output_index)
            when 'shell_call_output'
              merge_shell_output!(item, output_index)
            end

            @output_items_by_index[output_index] = item
          end

          def add_shell_command(event)
            output_index = event['output_index']
            command_index = event['command_index']
            command = event['command']
            return if output_index.nil? || command_index.nil? || command.nil?

            @shell_commands_by_output_index[output_index][command_index] = command

            item = @output_items_by_index[output_index]
            merge_shell_commands!(item, output_index) if item&.dig('type') == 'shell_call'
          end

          def add_shell_output_content(event)
            output_index = event['output_index']
            item_id = event['item_id']
            output = RubyLLM::Utils.deep_dup(event['output'] || [])

            @shell_outputs_by_item_id[item_id] = output if item_id
            @shell_outputs_by_output_index[output_index] = output unless output_index.nil?

            item = @output_items_by_index[output_index]
            merge_shell_output!(item, output_index) if item&.dig('type') == 'shell_call_output'
          end

          def merge_shell_commands!(item, output_index)
            return unless item

            commands_by_index = @shell_commands_by_output_index[output_index]
            return if commands_by_index.empty?

            action = item['action'] ||= {}
            commands = Array(action['commands'])

            commands_by_index.each do |command_index, command|
              commands[command_index] = command
            end

            action['commands'] = commands
          end

          def merge_shell_output!(item, output_index)
            return unless item

            output = @shell_outputs_by_item_id[item['id']] || @shell_outputs_by_output_index[output_index]
            item['output'] = RubyLLM::Utils.deep_dup(output) if output
          end

          def build_body
            body = RubyLLM::Utils.deep_dup(@completed_response || {})
            output = merged_output(body['output'])
            body['output'] = output if output.any? || body.key?('output')
            body
          end

          def build_default_response
            Class.new do
              def status
                200
              end

              def success?
                true
              end
            end.new
          end

          def merged_output(base_output)
            output_by_index = {}

            Array(base_output).each_with_index do |item, index|
              output_by_index[index] = RubyLLM::Utils.deep_dup(item)
            end

            @output_items_by_index.each do |index, item|
              output_by_index[index] = RubyLLM::Utils.deep_dup(item)
            end

            output_by_index.sort_by(&:first).map(&:last)
          end
        end

        module_function

        def stream_url
          'responses'
        end

        def stream_response(connection, payload, additional_headers = {}, &block)
          accumulator = StreamAccumulator.new
          completed_response = CompletedResponseAccumulator.new

          response = connection.post stream_url, payload do |req|
            req.headers = additional_headers.merge(req.headers) unless additional_headers.empty?
            apply_stream_on_data_handler(req, accumulator, completed_response, &block)
          end

          raw_response = completed_response.build_response(response)
          message = accumulator.to_message(raw_response)
          assign_response_id(message, raw_response)
          RubyLLM.logger.debug { "Stream completed: #{message.content}" }
          message
        end

        def build_chunk(data) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength
          event_type = data['type']

          case event_type
          when 'response.output_text.delta'
            # Text content delta
            Chunk.new(
              role: :assistant,
              content: data['delta'],
              model_id: data.dig('response', 'model')
            )

          when 'response.function_call_arguments.delta'
            # Function call arguments streaming
            Chunk.new(
              role: :assistant,
              content: nil,
              tool_calls: build_streaming_tool_call(data),
              model_id: data.dig('response', 'model')
            )

          when 'response.completed'
            # Final response with usage stats
            response_data = data['response'] || {}
            usage = response_data['usage'] || {}
            cached_tokens = usage.dig('input_tokens_details', 'cached_tokens')

            Chunk.new(
              role: :assistant,
              content: nil,
              input_tokens: usage['input_tokens'],
              output_tokens: usage['output_tokens'],
              cached_tokens: cached_tokens,
              cache_creation_tokens: 0,
              model_id: response_data['model'],
              response_id: response_data['id']
            )

          when 'response.output_item.added'
            # New output item started (function call, message, etc.)
            item = data['item'] || {}
            if item['type'] == 'function_call'
              Chunk.new(
                role: :assistant,
                content: nil,
                tool_calls: {
                  item['call_id'] => ToolCall.new(
                    id: item['call_id'],
                    name: item['name'],
                    arguments: ''
                  )
                }
              )
            else
              # Other item types - return empty chunk
              Chunk.new(role: :assistant, content: nil)
            end

          when 'response.content_part.added', 'response.content_part.done',
               'response.output_item.done', 'response.output_text.done',
               'response.function_call_arguments.done', 'response.created',
               'response.in_progress'
            # Status events - return empty chunk
            Chunk.new(role: :assistant, content: nil)

          when 'error'
            # Error event
            error_data = data['error'] || {}
            raise RubyLLM::Error.new(nil, error_data['message'] || 'Unknown streaming error')

          else
            # Unknown event type - return empty chunk
            Chunk.new(role: :assistant, content: nil)
          end
        end

        def build_streaming_tool_call(data)
          call_id = data['call_id'] || data['item_id']
          return nil unless call_id

          # Argument delta events don't carry a tool name — only the initial
          # output_item.added event does. Omit `id` on nameless deltas so
          # StreamAccumulator appends arguments to the latest tool call
          # instead of creating a new entry that overwrites the named one.
          {
            call_id => ToolCall.new(
              id: data['name'] ? call_id : nil,
              name: data['name'],
              arguments: data['delta'] || ''
            )
          }
        end

        def parse_streaming_error(data)
          error_data = JSON.parse(data)
          return unless error_data['error'] || error_data['type'] == 'error'

          error = error_data['error'] || error_data
          error_type = error['type'] || error['code']
          error_message = error['message']

          case error_type
          when 'server_error', 'internal_error'
            [500, error_message]
          when 'rate_limit_exceeded', 'insufficient_quota'
            [429, error_message]
          when 'invalid_request_error', 'invalid_api_key'
            [400, error_message]
          else
            [400, error_message]
          end
        rescue JSON::ParserError
          [500, data]
        end

        private

        def apply_stream_on_data_handler(req, accumulator, completed_response, &block)
          on_data = build_on_data_handler do |data|
            handle_stream_event(data, accumulator, completed_response, &block)
          end

          if faraday_1?
            req.options[:on_data] = on_data
          else
            req.options.on_data = on_data
          end
        end

        def handle_stream_event(data, accumulator, completed_response)
          return unless data.is_a?(Hash)

          completed_response.add(data)
          chunk = build_chunk(data)
          accumulator.add(chunk)
          yield chunk if block_given?
        end

        def assign_response_id(message, raw_response)
          return unless message.respond_to?(:response_id=)
          return unless raw_response.body.is_a?(Hash)

          message.response_id = raw_response.body['id']
        end
      end
    end
  end
end
