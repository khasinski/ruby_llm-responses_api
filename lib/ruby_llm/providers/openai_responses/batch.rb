# frozen_string_literal: true

require 'stringio'

module RubyLLM
  module Providers
    class OpenAIResponses
      # High-level interface for OpenAI's Batch API.
      # Hides JSONL serialization, file upload, polling, and result parsing
      # behind a clean Ruby API that mirrors RubyLLM::Chat.
      #
      # @example
      #   batch = RubyLLM.batch(model: 'gpt-4o', provider: :openai)
      #   batch.add("What is Ruby?")
      #   batch.add("What is Python?", instructions: "Be brief")
      #   batch.create!
      #   batch.wait! { |b| puts "#{b.completed_count}/#{b.total_count}" }
      #   batch.results  # => { "request_0" => Message, ... }
      class Batch
        attr_reader :id, :requests

        # @param model [String] Model ID (e.g. 'gpt-4o')
        # @param provider [Symbol, RubyLLM::Providers::OpenAIResponses, RubyLLM::Providers::OpenAI]
        #   Provider slug or instance
        # @param id [String, nil] Existing batch ID to resume
        def initialize(model: nil, provider: :openai, id: nil)
          @model = model
          @provider = resolve_provider(provider)
          @requests = []
          @request_counter = 0
          @data = {}

          return unless id

          @id = id
          refresh!
        end

        # Queue a request for inclusion in the batch.
        # @param input [String, Array] User message or Responses API input array
        # @param id [String, nil] Custom ID for this request (auto-generated if omitted)
        # @param instructions [String, nil] System/developer instructions
        # @param temperature [Float, nil] Sampling temperature
        # @param tools [Array, nil] Tools configuration
        # @return [self]
        def add(input, id: nil, instructions: nil, temperature: nil, tools: nil, **extra) # rubocop:disable Metrics/ParameterLists
          custom_id = id || "request_#{@request_counter}"
          @request_counter += 1

          body = { model: @model, input: Batches.normalize_input(input) }
          body[:instructions] = instructions if instructions
          body[:temperature] = temperature if temperature
          body[:tools] = tools if tools
          body.merge!(extra) unless extra.empty?

          @requests << { custom_id: custom_id, body: body }
          self
        end

        # Build JSONL, upload the file, and create the batch.
        # @param metadata [Hash, nil] Optional metadata for the batch
        # @return [self]
        def create!(metadata: nil)
          raise Error.new(nil, 'No requests added') if @requests.empty?
          raise Error.new(nil, 'Batch already created') if @id

          jsonl = Batches.build_jsonl(@requests)
          file_id = upload_file(jsonl)

          payload = {
            input_file_id: file_id,
            endpoint: '/v1/responses',
            completion_window: '24h'
          }
          payload[:metadata] = metadata if metadata

          response = @provider.instance_variable_get(:@connection).post(Batches.batches_url, payload)
          @data = response.body
          @id = @data['id']
          self
        end

        # Fetch the latest batch status from the API.
        # @return [self]
        def refresh!
          raise Error.new(nil, 'Batch not yet created') unless @id

          response = @provider.instance_variable_get(:@connection).get(Batches.batch_url(@id))
          @data = response.body
          self
        end

        # @return [String, nil] Batch status
        def status
          @data['status']
        end

        # @return [Integer, nil] Number of completed requests
        def completed_count
          @data.dig('request_counts', 'completed')
        end

        # @return [Integer, nil] Total number of requests
        def total_count
          @data.dig('request_counts', 'total')
        end

        # @return [Integer, nil] Number of failed requests
        def failed_count
          @data.dig('request_counts', 'failed')
        end

        # @return [Boolean]
        def completed?
          status == Batches::COMPLETED
        end

        # @return [Boolean]
        def in_progress?
          Batches.pending?(status)
        end

        # @return [Boolean]
        def failed?
          status == Batches::FAILED
        end

        # @return [Boolean]
        def expired?
          status == Batches::EXPIRED
        end

        # @return [Boolean]
        def cancelled?
          status == Batches::CANCELLED
        end

        # Block until the batch reaches a terminal status.
        # @param interval [Numeric] Seconds between polls (default: 30)
        # @param timeout [Numeric, nil] Maximum seconds to wait
        # @yield [Batch] Called after each poll
        # @return [self]
        def wait!(interval: 30, timeout: nil)
          start_time = Time.now

          loop do
            refresh!
            yield self if block_given?

            break if Batches.terminal?(status)

            if timeout && (Time.now - start_time) > timeout
              raise Error.new(nil, "Batch polling timeout after #{timeout} seconds")
            end

            sleep interval
          end

          self
        end

        # Download and parse the output file into a Hash of Messages.
        # @return [Hash<String, Message>] Results keyed by custom_id
        def results
          output_file_id = @data['output_file_id']
          raise Error.new(nil, 'No output file available yet') unless output_file_id

          jsonl = fetch_file_content(output_file_id)
          Batches.parse_results_to_messages(jsonl)
        end

        # Download and parse the error file.
        # @return [Array<Hash>] Error entries
        def errors
          error_file_id = @data['error_file_id']
          return [] unless error_file_id

          jsonl = fetch_file_content(error_file_id)
          Batches.parse_errors(jsonl)
        end

        # Cancel the batch.
        # @return [self]
        def cancel!
          raise Error.new(nil, 'Batch not yet created') unless @id

          response = @provider.instance_variable_get(:@connection).post(Batches.cancel_batch_url(@id), {})
          @data = response.body
          self
        end

        private

        def resolve_provider(provider)
          case provider
          when Symbol, String
            slug = provider.to_sym == :openai_responses ? :openai : provider.to_sym
            provider_class = RubyLLM::Provider.providers[slug]
            raise Error.new(nil, "Unknown provider: #{slug}") unless provider_class

            provider_class.new(RubyLLM.config)
          else
            provider
          end
        end

        # Upload a JSONL string as a file to the Files API.
        # @return [String] The uploaded file ID
        def upload_file(jsonl)
          io = StringIO.new(jsonl)
          file_part = Faraday::Multipart::FilePart.new(io, 'application/jsonl', 'batch_requests.jsonl')

          response = @provider.instance_variable_get(:@connection).post(Batches.files_url, {
                                                                          file: file_part,
                                                                          purpose: 'batch'
                                                                        })
          response.body['id']
        end

        # Download raw file content, bypassing JSON response middleware.
        # @return [String] Raw file content
        def fetch_file_content(file_id)
          conn = @provider.instance_variable_get(:@connection)
          response = conn.connection.get(Batches.file_content_url(file_id)) do |req|
            req.headers.merge!(@provider.headers)
          end
          response.body
        end
      end
    end
  end
end
