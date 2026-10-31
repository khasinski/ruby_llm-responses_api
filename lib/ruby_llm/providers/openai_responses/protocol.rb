# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Native Responses rendering/parsing, with state scoped to this provider.
      class Protocol < OpenAI::Responses
        def render(messages, provider_options: {}, **)
          @response_options = RubyLLM::Support::Utils.deep_symbolize_keys(provider_options)
          payload = super(messages, provider_options: @response_options.except(:transport), **)
          @store_response = payload[:store] != false
          payload
        end

        def render_payload(messages, **)
          state = @response_options || {}
          parent = if state.key?(:previous_response_id)
                     state[:previous_response_id]
                   elsif state[:store] != false
                     messages.rfind { |message| message.role == :assistant && message.response_id }&.response_id
                   end
          payload = super(new_messages(messages, parent), **)
          payload[:store] = state.fetch(:store, true)
          payload[:previous_response_id] = parent if parent
          payload
        end

        def apply_compaction(payload, compaction)
          warn_ignored_compaction_options(compaction)
          entry = { type: 'compaction' }
          entry[:compact_threshold] = compaction[:at] if compaction[:at]
          payload.merge(context_management: [entry])
        end

        def apply_end_user(payload, identifier)
          payload.merge(safety_identifier: identifier)
        end

        def supports_provider_file_references?
          true
        end

        def parse_completion_body(data, raw:)
          decorate_message(super, data)
        end

        def build_final_chunk(data)
          decorate_message(super, data.fetch('response', {}))
        end

        # Public event entry point for the standalone WebSocket client.
        def parse_event(data)
          build_chunk(data)
        end

        def stream_response(payload, additional_headers = {})
          accumulator = StreamAccumulator.new
          response = stream_events(stream_url, payload, additional_headers) do |data|
            chunk = build_chunk(data)
            accumulator.add(chunk)
            yield chunk
          end
          accumulator.to_message(response)
        end

        def stream_events(url, payload, additional_headers = {}, &)
          return super unless websocket?

          @usage_tracker&.start
          @provider.responses_websocket(additional_headers).stream_events(payload, &)
        end

        def sync_response(payload, additional_headers = {})
          return super unless websocket?

          stream_response(payload, additional_headers) { |chunk| @usage_tracker&.observe(chunk) }
        end

        private

        def websocket?
          @response_options && @response_options[:transport]&.to_sym == :websocket
        end

        def new_messages(messages, parent)
          return messages unless parent

          anchor = messages.rindex { |message| message.role == :assistant && message.response_id == parent }
          return messages unless anchor

          messages.each_with_index.filter_map { |message, index| message if message.role == :system || index > anchor }
        end

        def decorate_message(message, data)
          message.response_id = data['id'] unless @store_response == false || data['store'] == false
          message.built_in_tool_events = BuiltInTools.extract_events(data['output'] || [])
          message.responses_api_body = data
          message
        end
      end
    end
  end
end
