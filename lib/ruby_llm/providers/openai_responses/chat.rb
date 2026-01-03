# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Chat completion methods for the OpenAI Responses API.
      # Handles converting RubyLLM messages to Responses API format and parsing responses.
      module Chat
        def completion_url
          'responses'
        end

        module_function

        def render_payload(messages, tools:, temperature:, model:, stream: false, schema: nil) # rubocop:disable Metrics/ParameterLists
          # Extract system messages for instructions
          system_messages = messages.select { |m| m.role == :system }
          non_system_messages = messages.reject { |m| m.role == :system }

          instructions = system_messages.map { |m| extract_text_content(m.content) }.join("\n\n")

          payload = {
            model: model.id,
            input: format_input(non_system_messages),
            stream: stream
          }

          payload[:instructions] = instructions unless instructions.empty?
          payload[:temperature] = temperature unless temperature.nil?

          payload[:tools] = tools.map { |_, tool| tool_for(tool) } if tools.any?

          if schema
            payload[:text] = {
              format: {
                type: 'json_schema',
                name: 'response',
                schema: schema,
                strict: schema[:strict] != false
              }
            }
          end

          # Auto-chain conversations: find the last response_id from assistant messages
          # This enables automatic stateful conversations without manual tracking
          last_response_id = extract_last_response_id(messages)
          payload[:previous_response_id] = last_response_id if last_response_id

          payload
        end

        def extract_last_response_id(messages)
          messages
            .select { |m| m.role == :assistant && m.respond_to?(:response_id) }
            .map(&:response_id)
            .compact
            .last
        end

        def parse_completion_response(response)
          data = response.body
          return if data.nil? || data.empty?

          data = JSON.parse(data) if data.is_a?(String)

          raise RubyLLM::Error.new(response, data.dig('error', 'message')) if data.dig('error', 'message')

          output = data['output'] || []

          # Extract text content from output
          content = extract_output_text(output)

          # Extract tool calls from function_call outputs
          tool_calls = extract_tool_calls(output)

          usage = data['usage'] || {}
          cached_tokens = usage.dig('input_tokens_details', 'cached_tokens')

          Message.new(
            role: :assistant,
            content: content,
            tool_calls: tool_calls,
            input_tokens: usage['input_tokens'],
            output_tokens: usage['output_tokens'],
            cached_tokens: cached_tokens,
            cache_creation_tokens: 0,
            model_id: data['model'],
            response_id: data['id'],
            raw: response
          )
        end

        def format_input(messages) # rubocop:disable Metrics/MethodLength
          result = []

          messages.each do |msg|
            if msg.tool_call_id
              # Tool result message - function_call_output type
              result << {
                type: 'function_call_output',
                call_id: msg.tool_call_id,
                output: extract_text_content(msg.content)
              }
            elsif msg.tool_calls&.any?
              # Assistant message with tool calls
              # First add any text content as a message
              text = extract_text_content(msg.content)
              if text && !text.empty?
                result << {
                  type: 'message',
                  role: 'assistant',
                  content: text
                }
              end

              # Then add each function call as a separate item
              msg.tool_calls.each_value do |tc|
                result << {
                  type: 'function_call',
                  call_id: tc.id,
                  name: tc.name,
                  arguments: tc.arguments.is_a?(String) ? tc.arguments : JSON.generate(tc.arguments)
                }
              end
            else
              # Regular message
              result << {
                type: 'message',
                role: format_role(msg.role),
                content: format_message_content(msg.content, nil)
              }
            end
          end

          result
        end

        def format_message_content(content, tool_calls = nil)
          parts = []

          # Add text content
          text = extract_text_content(content)
          parts << { type: 'input_text', text: text } if text && !text.empty?

          # Add attachments if present
          if content.is_a?(RubyLLM::Content)
            content.attachments.each do |attachment|
              parts << format_attachment(attachment)
            end
          end

          # Add tool calls if present (for assistant messages)
          if tool_calls&.any?
            tool_calls.each_value do |tc|
              parts << {
                type: 'function_call',
                call_id: tc.id,
                name: tc.name,
                arguments: tc.arguments.is_a?(String) ? tc.arguments : JSON.generate(tc.arguments)
              }
            end
          end

          # Return simple text for single text content
          return parts.first[:text] if parts.length == 1 && parts.first[:type] == 'input_text'

          parts
        end

        def format_attachment(attachment)
          case attachment.type
          when :image
            if attachment.url?
              { type: 'input_image', image_url: attachment.source }
            else
              { type: 'input_image', image_url: attachment.for_llm }
            end
          when :pdf
            {
              type: 'input_file',
              filename: File.basename(attachment.source.to_s),
              file_data: attachment.for_llm
            }
          when :audio
            {
              type: 'input_audio',
              data: attachment.for_llm,
              format: detect_audio_format(attachment.source)
            }
          else
            { type: 'input_text', text: "[Unsupported attachment: #{attachment.type}]" }
          end
        end

        def detect_audio_format(source)
          ext = File.extname(source.to_s).downcase
          case ext
          when '.mp3' then 'mp3'
          when '.wav' then 'wav'
          when '.webm' then 'webm'
          when '.ogg' then 'ogg'
          when '.flac' then 'flac'
          else 'mp3'
          end
        end

        def extract_text_content(content)
          case content
          when String
            content
          when RubyLLM::Content
            content.text
          when Hash
            content[:text] || content['text']
          else
            content.to_s
          end
        end

        def format_role(role)
          case role
          when :system then 'developer'
          when :assistant then 'assistant'
          when :tool then 'user' # Tool results come from user perspective
          else role.to_s
          end
        end

        def extract_output_text(output)
          output
            .select { |item| item['type'] == 'message' }
            .flat_map { |item| item['content'] || [] }
            .select { |c| c['type'] == 'output_text' }
            .map { |c| c['text'] }
            .join
        end

        def extract_tool_calls(output)
          function_calls = output.select { |item| item['type'] == 'function_call' }
          return nil if function_calls.empty?

          function_calls.to_h do |fc|
            [
              fc['call_id'],
              ToolCall.new(
                id: fc['call_id'],
                name: fc['name'],
                arguments: parse_arguments(fc['arguments'])
              )
            ]
          end
        end

        def parse_arguments(arguments)
          return {} if arguments.nil? || arguments.empty?
          return arguments if arguments.is_a?(Hash)

          JSON.parse(arguments)
        rescue JSON::ParserError
          { raw: arguments }
        end
      end
    end
  end
end
