# frozen_string_literal: true

require 'json'

module RubyLLM
  module Providers
    class OpenAIResponses
      # Stateless helpers for the Batch API.
      # Provides URL builders, JSONL serialization, status constants, and result parsing.
      module Batches
        module_function

        # Status constants
        VALIDATING = 'validating'
        IN_PROGRESS = 'in_progress'
        COMPLETED = 'completed'
        FAILED = 'failed'
        CANCELLED = 'cancelled'
        CANCELLING = 'cancelling'
        EXPIRED = 'expired'

        TERMINAL_STATUSES = [COMPLETED, FAILED, CANCELLED, EXPIRED].freeze
        PENDING_STATUSES = [VALIDATING, IN_PROGRESS, CANCELLING].freeze

        # --- URL helpers ---

        def files_url
          'files'
        end

        def batches_url
          'batches'
        end

        def batch_url(batch_id)
          "batches/#{batch_id}"
        end

        def cancel_batch_url(batch_id)
          "batches/#{batch_id}/cancel"
        end

        def file_content_url(file_id)
          "files/#{file_id}/content"
        end

        # --- Status helpers ---

        def terminal?(status)
          TERMINAL_STATUSES.include?(status)
        end

        def pending?(status)
          PENDING_STATUSES.include?(status)
        end

        # --- JSONL builder ---

        # Build a JSONL string from an array of request hashes.
        # Each request has: custom_id, body (the Responses API payload)
        def build_jsonl(requests)
          requests.map do |req|
            JSON.generate({
                            custom_id: req[:custom_id],
                            method: 'POST',
                            url: '/v1/responses',
                            body: req[:body]
                          })
          end.join("\n")
        end

        # --- Input normalization ---

        # Wraps a plain string into the Responses API input format.
        def normalize_input(input)
          case input
          when String
            [{ type: 'message', role: 'user', content: input }]
          when Array
            input
          else
            input
          end
        end

        # --- Result parsing ---

        # Parse JSONL output into an array of raw result hashes.
        def parse_results(jsonl_string)
          jsonl_string.each_line.filter_map do |line|
            line = line.strip
            next if line.empty?

            JSON.parse(line)
          end
        end

        # Parse JSONL output into a Hash of { custom_id => Message }.
        # Uses the native Responses parser, including reasoning and server tools.
        def parse_results_to_messages(jsonl_string)
          results = parse_results(jsonl_string)
          results.each_with_object({}) do |result, hash|
            custom_id = result['custom_id']
            response_body = result.dig('response', 'body')
            next unless response_body

            next if result.dig('response', 'status_code').to_i >= 400

            raw = Faraday::Response.new(status: result.dig('response', 'status_code') || 200, body: response_body)
            provider = OpenAIResponses.new(RubyLLM.config)
            hash[custom_id] = Protocol.new(provider).parse_completion_body(response_body, raw: raw)
          end
        end

        # Parse JSONL error file into an array of error hashes.
        def parse_errors(jsonl_string)
          results = parse_results(jsonl_string)
          results.select { |r| r.dig('response', 'status_code')&.>= 400 }
        end
      end
    end
  end
end
