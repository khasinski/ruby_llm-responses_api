# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Extra provider methods for RubyLLM's native OpenAI provider.
      module NativeProviderExtension
        # rubocop:disable Metrics/ParameterLists
        def complete(messages, tools:, temperature:, model:, params: {}, headers: {},
                     schema: nil, thinking: nil, citations: false, tool_prefs: nil, protocol: nil, &block)
          if params[:transport]&.to_sym == :websocket
            ws_complete(
              messages,
              tools: tools,
              temperature: temperature,
              model: model,
              params: params.except(:transport),
              schema: schema,
              thinking: thinking,
              citations: citations,
              tool_prefs: tool_prefs,
              &block
            )
          else
            super
          end
        end
        # rubocop:enable Metrics/ParameterLists

        def retrieve_response(response_id)
          @connection.get(Background.retrieve_url(response_id)).body
        end

        def cancel_response(response_id)
          @connection.post(Background.cancel_url(response_id), {}).body
        end

        def delete_response(response_id)
          delete_request(Background.retrieve_url(response_id)).body
        end

        def list_input_items(response_id)
          @connection.get(Background.input_items_url(response_id)).body
        end

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

        def compact_response(model:, input:, **params)
          @connection.post(Compaction.compact_url, { model: model, input: input }.merge(params)).body
        end

        def count_input_tokens(model:, input:, **params)
          @connection.post(Compaction.input_tokens_url, { model: model, input: input }.merge(params)).body
        end

        def create_container(name: nil, expires_after: nil, file_ids: nil, memory_limit: nil)
          payload = Containers.create_payload(
            name: name,
            expires_after: expires_after,
            file_ids: file_ids,
            memory_limit: memory_limit
          )
          @connection.post(Containers.containers_url, payload).body
        end

        def retrieve_container(container_id)
          @connection.get(Containers.container_url(container_id)).body
        end

        def delete_container(container_id)
          delete_request(Containers.container_url(container_id)).body
        end

        def list_container_files(container_id)
          @connection.get(Containers.container_files_url(container_id)).body
        end

        def retrieve_container_file(container_id, file_id)
          @connection.get(Containers.container_file_url(container_id, file_id)).body
        end

        def retrieve_container_file_content(container_id, file_id)
          @connection.get(Containers.container_file_content_url(container_id, file_id)).body
        end

        def list_batches(limit: 20, after: nil)
          params = { limit: limit }
          params[:after] = after if after

          @connection.get(Batches.batches_url) do |req|
            req.params.merge!(params)
          end.body
        end

        private

        # rubocop:disable Metrics/ParameterLists
        def ws_complete(messages, tools:, temperature:, model:, params:, schema:, thinking:,
                        citations:, tool_prefs:, &block)
          # rubocop:enable Metrics/ParameterLists
          protocol = RubyLLM::Protocols::Responses.new(self, model)
          normalized_temperature = protocol.maybe_normalize_temperature(temperature, model)

          payload = RubyLLM::Utils.deep_merge(
            protocol.__send__(
              :render_payload,
              messages,
              tools: tools,
              tool_prefs: tool_prefs,
              temperature: normalized_temperature,
              model: model,
              stream: true,
              schema: schema,
              thinking: thinking,
              citations: citations
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

        def delete_request(url)
          payload = { provider: slug, method: :delete, url: url }

          instrument_request(payload) do
            response = @connection.connection.delete(url) do |req|
              req.headers.merge!(headers)
            end
            payload[:status] = response.status if response.respond_to?(:status)
            response
          end
        end

        def instrument_request(payload, &)
          return yield unless RubyLLM.respond_to?(:instrument)

          RubyLLM.instrument('request.ruby_llm', payload, config: @config, &)
        end
      end

      # Adds the gem's server-side state and built-in tool observability on top
      # of RubyLLM's native Responses protocol.
      module NativeResponsesExtension
        # rubocop:disable Metrics/ParameterLists
        def render_payload(messages, tools:, temperature:, model:, stream: false, schema: nil,
                           thinking: nil, citations: false, tool_prefs: nil)
          last_response_id = OpenAIResponses.extract_last_response_id(messages)
          payload_messages = if last_response_id
                               system, non_system = messages.partition { |message| message.role == :system }
                               system + OpenAIResponses.unchained_messages(non_system, last_response_id)
                             else
                               messages
                             end

          payload = super(
            payload_messages,
            tools: tools,
            temperature: temperature,
            model: model,
            stream: stream,
            schema: schema,
            thinking: thinking,
            citations: citations,
            tool_prefs: tool_prefs
          )

          # Native RubyLLM defaults to store: false. This gem's stateful mode
          # relies on OpenAI storing response IDs, while callers can still pass
          # with_params(store: false) to override during RubyLLM's params merge.
          payload.delete(:store)
          payload[:previous_response_id] = last_response_id if last_response_id
          payload
        end
        # rubocop:enable Metrics/ParameterLists

        def parse_completion_response(response)
          data = response.body
          data = JSON.parse(data) if data.is_a?(String)

          message = super
          return message unless message

          message.response_id = data['id'] if message.respond_to?(:response_id=)

          events = BuiltInTools.extract_events(data['output'] || [])
          message.built_in_tool_events = events if message.respond_to?(:built_in_tool_events=) && events.any?
          message
        end

        def build_completed_chunk(data)
          chunk = super
          response = data['response'] || {}

          chunk.response_id = response['id'] if chunk.respond_to?(:response_id=)

          events = BuiltInTools.extract_events(response['output'] || [])
          chunk.built_in_tool_events = events if chunk.respond_to?(:built_in_tool_events=) && events.any?
          chunk
        end
      end

      module NativeProviderAlias
        def resolve(model_id, provider: nil, assume_exists: false, config: nil)
          provider = :openai if provider&.to_sym == :openai_responses

          super
        end
      end

      class << self
        def extract_last_response_id(messages)
          messages
            .select { |message| message.role == :assistant && message.respond_to?(:response_id) }
            .map(&:response_id)
            .compact
            .last
        end

        def unchained_messages(messages, last_response_id)
          return messages unless last_response_id

          anchor = messages.rindex do |message|
            message.role == :assistant &&
              message.respond_to?(:response_id) &&
              message.response_id == last_response_id
          end
          return messages unless anchor

          messages[(anchor + 1)..] || []
        end
      end
    end
  end
end

RubyLLM::Chunk.class_eval do
  attr_accessor :response_id, :built_in_tool_events
end

RubyLLM::Providers::OpenAI.prepend(
  RubyLLM::Providers::OpenAIResponses::NativeProviderExtension
)

RubyLLM::Protocols::Responses.prepend(
  RubyLLM::Providers::OpenAIResponses::NativeResponsesExtension
)

RubyLLM::Models.singleton_class.prepend(
  RubyLLM::Providers::OpenAIResponses::NativeProviderAlias
)
