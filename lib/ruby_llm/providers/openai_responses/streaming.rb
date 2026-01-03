# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Streaming methods for the OpenAI Responses API.
      # Handles SSE events with typed event format.
      module Streaming
        module_function

        def stream_url
          'responses'
        end

        def build_chunk(data) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
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
              Chunk.new(role: :assistant)
            end

          when 'response.content_part.added', 'response.content_part.done',
               'response.output_item.done', 'response.output_text.done',
               'response.function_call_arguments.done', 'response.created',
               'response.in_progress'
            # Status events - return empty chunk
            Chunk.new(role: :assistant)

          when 'error'
            # Error event
            error_data = data['error'] || {}
            raise RubyLLM::Error, error_data['message'] || 'Unknown streaming error'

          else
            # Unknown event type - return empty chunk
            Chunk.new(role: :assistant)
          end
        end

        def build_streaming_tool_call(data)
          call_id = data['call_id'] || data['item_id']
          return nil unless call_id

          {
            call_id => ToolCall.new(
              id: call_id,
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
      end
    end
  end
end
