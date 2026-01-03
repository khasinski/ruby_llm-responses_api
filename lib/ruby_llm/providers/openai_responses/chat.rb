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

        def render_payload(messages, tools:, temperature:, model:, stream: false, schema: nil) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/ParameterLists,Metrics/PerceivedComplexity
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

          if tools.any?
            payload[:tools] = tools.map { |_, tool| tool_for(tool) }
          end

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

          payload
        end

        def parse_completion_response(response) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
          data = response.body
          return if data.nil? || data.empty?

          if data.is_a?(String)
            data = JSON.parse(data)
          end

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
          messages.map do |msg|
            item = {
              type: 'message',
              role: format_role(msg.role)
            }

            if msg.tool_call_id
              # Tool result message
              item[:type] = 'function_call_output'
              item[:call_id] = msg.tool_call_id
              item[:output] = extract_text_content(msg.content)
              item.delete(:role)
            else
              item[:content] = format_content(msg.content, msg.tool_calls)
            end

            item
          end
        end

        def format_content(content, tool_calls = nil)
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
            tool_calls.each do |_, tc|
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
