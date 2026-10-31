# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::OpenAIResponses::Batch do
  include ResponseHelpers

  let(:connection) { instance_double(RubyLLM::Transport::Connection) }
  let(:faraday_connection) { instance_double(Faraday::Connection) }
  let(:provider) do
    instance_double(
      RubyLLM::Providers::OpenAIResponses,
      headers: { 'Authorization' => 'Bearer test-key' }
    )
  end

  before do
    allow(provider).to receive(:instance_variable_get).with(:@connection).and_return(connection)
    allow(connection).to receive(:connection).and_return(faraday_connection)
  end

  describe '#add' do
    it 'queues requests with auto-generated IDs' do
      batch = described_class.new(model: 'gpt-4o', provider: provider)
      batch.add('What is Ruby?')
      batch.add('What is Python?')

      expect(batch.requests.length).to eq(2)
      expect(batch.requests[0][:custom_id]).to eq('request_0')
      expect(batch.requests[1][:custom_id]).to eq('request_1')
    end

    it 'queues requests with explicit IDs' do
      batch = described_class.new(model: 'gpt-4o', provider: provider)
      batch.add('What is Ruby?', id: 'ruby_q')
      batch.add('What is Python?', id: 'python_q')

      expect(batch.requests[0][:custom_id]).to eq('ruby_q')
      expect(batch.requests[1][:custom_id]).to eq('python_q')
    end

    it 'normalizes string input' do
      batch = described_class.new(model: 'gpt-4o', provider: provider)
      batch.add('Hello')

      body = batch.requests[0][:body]
      expect(body[:input]).to eq([{ type: 'message', role: 'user', content: 'Hello' }])
    end

    it 'includes optional parameters' do
      batch = described_class.new(model: 'gpt-4o', provider: provider)
      batch.add('Hello', instructions: 'Be brief', temperature: 0.5)

      body = batch.requests[0][:body]
      expect(body[:instructions]).to eq('Be brief')
      expect(body[:temperature]).to eq(0.5)
    end

    it 'includes extra keyword arguments' do
      batch = described_class.new(model: 'gpt-4o', provider: provider)
      batch.add('Hello', store: true)

      body = batch.requests[0][:body]
      expect(body[:store]).to be true
    end

    it 'returns self for chaining' do
      batch = described_class.new(model: 'gpt-4o', provider: provider)
      result = batch.add('Hello')
      expect(result).to be(batch)
    end
  end

  describe '#create!' do
    let(:upload_response) { mock_response({ 'id' => 'file_abc123' }) }
    let(:batch_response) do
      mock_response({
                      'id' => 'batch_abc123',
                      'status' => 'validating',
                      'request_counts' => { 'total' => 2, 'completed' => 0, 'failed' => 0 }
                    })
    end

    before do
      allow(connection).to receive(:post).with('files', anything).and_return(upload_response)
      allow(connection).to receive(:post).with('batches', anything).and_return(batch_response)
    end

    it 'uploads JSONL file and creates batch' do
      batch = described_class.new(model: 'gpt-4o', provider: provider)
      batch.add('What is Ruby?')
      batch.add('What is Python?')
      batch.create!

      expect(connection).to have_received(:post).with('files', hash_including(:file, :purpose))
      expect(connection).to have_received(:post).with('batches', hash_including(
                                                                   input_file_id: 'file_abc123',
                                                                   endpoint: '/v1/responses',
                                                                   completion_window: '24h'
                                                                 ))
      expect(batch.id).to eq('batch_abc123')
    end

    it 'includes metadata when provided' do
      batch = described_class.new(model: 'gpt-4o', provider: provider)
      batch.add('Hello')
      batch.create!(metadata: { team: 'engineering' })

      expect(connection).to have_received(:post).with('batches', hash_including(
                                                                   metadata: { team: 'engineering' }
                                                                 ))
    end

    it 'raises if no requests added' do
      batch = described_class.new(model: 'gpt-4o', provider: provider)
      expect { batch.create! }.to raise_error(RubyLLM::Error, 'No requests added')
    end

    it 'raises if batch already created' do
      batch = described_class.new(model: 'gpt-4o', provider: provider)
      batch.add('Hello')
      batch.create!

      expect { batch.create! }.to raise_error(RubyLLM::Error, 'Batch already created')
    end
  end

  describe '#refresh!' do
    it 'fetches latest batch status' do
      refresh_response = mock_response({
                                         'id' => 'batch_abc123',
                                         'status' => 'in_progress',
                                         'request_counts' => { 'total' => 2, 'completed' => 1, 'failed' => 0 }
                                       })

      allow(connection).to receive(:get).with('batches/batch_abc123').and_return(refresh_response)

      batch = described_class.new(model: 'gpt-4o', provider: provider)
      # Set the ID directly to simulate a created batch
      batch.instance_variable_set(:@id, 'batch_abc123')
      batch.instance_variable_set(:@data, { 'id' => 'batch_abc123' })

      batch.refresh!
      expect(batch.status).to eq('in_progress')
      expect(batch.completed_count).to eq(1)
      expect(batch.total_count).to eq(2)
    end

    it 'raises if batch not yet created' do
      batch = described_class.new(model: 'gpt-4o', provider: provider)
      expect { batch.refresh! }.to raise_error(RubyLLM::Error, 'Batch not yet created')
    end
  end

  describe '#wait!' do
    it 'polls until terminal status' do
      responses = [
        mock_response({
                        'id' => 'batch_abc123', 'status' => 'in_progress',
                        'request_counts' => { 'total' => 2, 'completed' => 1, 'failed' => 0 }
                      }),
        mock_response({
                        'id' => 'batch_abc123', 'status' => 'completed',
                        'request_counts' => { 'total' => 2, 'completed' => 2, 'failed' => 0 }
                      })
      ]

      call_count = 0
      allow(connection).to receive(:get).with('batches/batch_abc123') do
        resp = responses[call_count]
        call_count += 1
        resp
      end

      batch = described_class.new(model: 'gpt-4o', provider: provider)
      batch.instance_variable_set(:@id, 'batch_abc123')
      batch.instance_variable_set(:@data, { 'id' => 'batch_abc123' })

      # Use a tiny interval to speed up the test
      allow(batch).to receive(:sleep)

      statuses = []
      batch.wait!(interval: 0.01) { |b| statuses << b.status }

      expect(statuses).to eq(%w[in_progress completed])
      expect(batch.completed?).to be true
    end

    it 'yields on each poll' do
      response = mock_response({
                                 'id' => 'batch_abc123', 'status' => 'completed',
                                 'request_counts' => { 'total' => 1, 'completed' => 1, 'failed' => 0 }
                               })
      allow(connection).to receive(:get).with('batches/batch_abc123').and_return(response)

      batch = described_class.new(model: 'gpt-4o', provider: provider)
      batch.instance_variable_set(:@id, 'batch_abc123')
      batch.instance_variable_set(:@data, { 'id' => 'batch_abc123' })

      yielded = false
      batch.wait!(interval: 0.01) { |_b| yielded = true }
      expect(yielded).to be true
    end

    it 'respects timeout' do
      response = mock_response({
                                 'id' => 'batch_abc123', 'status' => 'in_progress',
                                 'request_counts' => { 'total' => 2, 'completed' => 0, 'failed' => 0 }
                               })
      allow(connection).to receive(:get).with('batches/batch_abc123').and_return(response)

      batch = described_class.new(model: 'gpt-4o', provider: provider)
      batch.instance_variable_set(:@id, 'batch_abc123')
      batch.instance_variable_set(:@data, { 'id' => 'batch_abc123' })
      allow(batch).to receive(:sleep)

      expect { batch.wait!(interval: 0.01, timeout: 0.001) }
        .to raise_error(RubyLLM::Error, /timeout/)
    end
  end

  describe '#results' do
    it 'downloads and parses output file to Messages' do
      batch = described_class.new(model: 'gpt-4o', provider: provider)
      batch.instance_variable_set(:@id, 'batch_abc123')
      batch.instance_variable_set(:@data, {
                                    'id' => 'batch_abc123',
                                    'status' => 'completed',
                                    'output_file_id' => 'file_output_123'
                                  })

      jsonl_content = JSON.generate({
                                      custom_id: 'request_0',
                                      response: {
                                        status_code: 200,
                                        body: {
                                          model: 'gpt-4o',
                                          output: [
                                            { type: 'message', role: 'assistant',
                                              content: [{ type: 'output_text', text: 'Ruby is great!' }] }
                                          ],
                                          usage: { input_tokens: 10, output_tokens: 5 }
                                        }
                                      }
                                    })

      raw_response = instance_double(Faraday::Response, body: jsonl_content)
      allow(faraday_connection).to receive(:get).with('files/file_output_123/content').and_yield(
        double(headers: {})
      ).and_return(raw_response)

      results = batch.results
      expect(results).to be_a(Hash)
      expect(results['request_0']).to be_a(RubyLLM::Message)
      expect(results['request_0'].content).to eq('Ruby is great!')
    end

    it 'raises if no output file yet' do
      batch = described_class.new(model: 'gpt-4o', provider: provider)
      batch.instance_variable_set(:@id, 'batch_abc123')
      batch.instance_variable_set(:@data, { 'id' => 'batch_abc123', 'status' => 'in_progress' })

      expect { batch.results }.to raise_error(RubyLLM::Error, /No output file/)
    end
  end

  describe '#errors' do
    it 'downloads and parses error file' do
      batch = described_class.new(model: 'gpt-4o', provider: provider)
      batch.instance_variable_set(:@id, 'batch_abc123')
      batch.instance_variable_set(:@data, {
                                    'id' => 'batch_abc123',
                                    'status' => 'completed',
                                    'error_file_id' => 'file_error_123'
                                  })

      jsonl_content = JSON.generate({
                                      custom_id: 'request_1',
                                      response: { status_code: 400, body: { error: { message: 'Bad request' } } }
                                    })

      raw_response = instance_double(Faraday::Response, body: jsonl_content)
      allow(faraday_connection).to receive(:get).with('files/file_error_123/content').and_yield(
        double(headers: {})
      ).and_return(raw_response)

      errors = batch.errors
      expect(errors.length).to eq(1)
      expect(errors[0]['custom_id']).to eq('request_1')
    end

    it 'returns empty array if no error file' do
      batch = described_class.new(model: 'gpt-4o', provider: provider)
      batch.instance_variable_set(:@id, 'batch_abc123')
      batch.instance_variable_set(:@data, { 'id' => 'batch_abc123', 'status' => 'completed' })

      expect(batch.errors).to eq([])
    end
  end

  describe '#cancel!' do
    it 'posts cancel request' do
      cancel_response = mock_response({
                                        'id' => 'batch_abc123',
                                        'status' => 'cancelling'
                                      })
      allow(connection).to receive(:post).with('batches/batch_abc123/cancel', {}).and_return(cancel_response)

      batch = described_class.new(model: 'gpt-4o', provider: provider)
      batch.instance_variable_set(:@id, 'batch_abc123')
      batch.instance_variable_set(:@data, { 'id' => 'batch_abc123' })

      batch.cancel!
      expect(batch.status).to eq('cancelling')
    end

    it 'raises if batch not yet created' do
      batch = described_class.new(model: 'gpt-4o', provider: provider)
      expect { batch.cancel! }.to raise_error(RubyLLM::Error, 'Batch not yet created')
    end
  end

  describe 'status helpers' do
    let(:batch) { described_class.new(model: 'gpt-4o', provider: provider) }

    before do
      batch.instance_variable_set(:@id, 'batch_abc123')
    end

    it '#completed? returns true when completed' do
      batch.instance_variable_set(:@data, { 'status' => 'completed' })
      expect(batch.completed?).to be true
      expect(batch.in_progress?).to be false
    end

    it '#in_progress? returns true for pending statuses' do
      batch.instance_variable_set(:@data, { 'status' => 'in_progress' })
      expect(batch.in_progress?).to be true
      expect(batch.completed?).to be false
    end

    it '#failed? returns true when failed' do
      batch.instance_variable_set(:@data, { 'status' => 'failed' })
      expect(batch.failed?).to be true
    end

    it '#expired? returns true when expired' do
      batch.instance_variable_set(:@data, { 'status' => 'expired' })
      expect(batch.expired?).to be true
    end

    it '#cancelled? returns true when cancelled' do
      batch.instance_variable_set(:@data, { 'status' => 'cancelled' })
      expect(batch.cancelled?).to be true
    end
  end

  describe 'resume from ID' do
    it 'fetches batch data on initialization with id:' do
      refresh_response = mock_response({
                                         'id' => 'batch_abc123',
                                         'status' => 'completed',
                                         'request_counts' => { 'total' => 3, 'completed' => 3, 'failed' => 0 },
                                         'output_file_id' => 'file_out'
                                       })
      allow(connection).to receive(:get).with('batches/batch_abc123').and_return(refresh_response)

      batch = described_class.new(provider: provider, id: 'batch_abc123')
      expect(batch.id).to eq('batch_abc123')
      expect(batch.status).to eq('completed')
      expect(batch.total_count).to eq(3)
    end
  end

  describe 'namespace access' do
    it 'is accessible via RubyLLM::ResponsesAPI::Batch' do
      expect(RubyLLM::ResponsesAPI::Batch).to eq(described_class)
    end
  end
end
