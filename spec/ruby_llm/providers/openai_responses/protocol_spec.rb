# frozen_string_literal: true

require 'spec_helper'

class MigrationWeather < RubyLLM::Tool
  description 'Weather lookup'
  parameter :city, type: 'string'

  def execute(city:)
    "Sunny in #{city}"
  end
end

RSpec.describe 'Native Responses integration' do
  let(:chat) { RubyLLM.chat(model: 'gpt-4o', provider: :openai_responses) }
  let(:requests) { [] }

  def completion(id, text = 'Hello', **extra)
    sample_completion_response.merge('id' => id, 'output' => [
                                       { 'type' => 'message', 'role' => 'assistant',
                                         'content' => [{ 'type' => 'output_text', 'text' => text }] }
                                     ]).merge(extra.transform_keys(&:to_s))
  end

  def stub_completions(*bodies)
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      requests << JSON.parse(request.body)
      { status: 200, body: JSON.generate(bodies.shift), headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def stub_streams(*bodies)
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      requests << JSON.parse(request.body)
      body = bodies.shift
      events = [
        { 'type' => 'response.output_text.delta', 'delta' => 'Hello' },
        { 'type' => "response.#{body.fetch('status', 'completed')}", 'response' => body }
      ]
      { status: 200, body: build_sse_body(events), headers: { 'Content-Type' => 'text/event-stream' } }
    end
  end

  it 'chains sync turns using only new input and resends current instructions' do
    stub_completions(completion('resp_1'), completion('resp_2'), completion('resp_3'))
    chat.with_instructions('Be brief')
    3.times { |i| chat.ask("Turn #{i}") }
    expect(requests.map { |r| r['previous_response_id'] }).to eq([nil, 'resp_1', 'resp_2'])
    expect(requests.map { |r| r['input'].map { |m| m['content'] } }).to eq([['Turn 0'], ['Turn 1'], ['Turn 2']])
    expect(requests.map { |r| r['instructions'] }).to eq(['Be brief'] * 3)
    expect(requests.map { |r| r['store'] }).to eq([true] * 3)
    expect(chat.messages.last.response_id).to eq('resp_3')
  end

  it 'chains streamed turns and preserves native metadata and raw output' do
    body = completion('resp_1', output: [{ 'type' => 'shell_call', 'id' => 'shell_1', 'status' => 'completed',
                                           'action' => { 'commands' => ['pwd'] } }])
    stub_streams(body, completion('resp_2'))
    seen = []
    chat.before_tool_call { |call| seen << call.name }
    first = chat.ask('Run pwd') { |_chunk| }
    chat.ask('Next') { |_chunk| }
    expect(first.response_id).to eq('resp_1')
    expect(first.raw.body).to eq(body)
    expect(first.server_tool_calls.first.raw['id']).to eq('shell_1')
    expect(first.tokens.input).to eq(10)
    expect(chat.usage_entries).not_to be_empty
    expect(seen).to eq(['shell'])
    expect(requests.last['input']).to eq([{ 'role' => 'user', 'content' => 'Next' }])
    expect(requests.last['previous_response_id']).to eq('resp_1')
  end

  it 'can switch from streaming to sync without replaying history' do
    stub_streams(completion('resp_1'))
    chat.ask('First') { |_chunk| }
    stub_completions(completion('resp_2'))
    chat.ask('Second')
    expect(requests.last['previous_response_id']).to eq('resp_1')
    expect(requests.last['input'].size).to eq(1)
  end

  it 'replays the whole history and keeps encrypted reasoning with store false' do
    stub_completions(completion('resp_1'), completion('resp_2'))
    chat.with_provider_options(store: false)
    expect(chat.ask('First').response_id).to be_nil
    chat.ask('Second')
    expect(requests.last['store']).to be(false)
    expect(requests.last).not_to have_key('previous_response_id')
    expect(requests.last['input'].size).to eq(3)
    expect(requests.last['include']).to include('reasoning.encrypted_content')
  end

  it 'can disable chaining explicitly while retaining storage' do
    stub_completions(completion('resp_1'), completion('resp_2'))
    chat.ask('First')
    chat.with_provider_options(previous_response_id: nil).ask('Second')
    expect(requests.last['previous_response_id']).to be_nil
    expect(requests.last['input'].size).to eq(3)
  end

  it 'does not automatically chain a previous response when store is disabled later' do
    stub_completions(completion('resp_1'), completion('resp_2'))
    chat.ask('First')
    chat.with_provider_options(store: false).ask('Second')
    expect(requests.last).not_to have_key('previous_response_id')
    expect(requests.last['input'].size).to eq(3)
  end

  it 'supports an explicit parent from another session' do
    stub_completions(completion('resp_next'))
    chat.with_provider_options(previous_response_id: 'resp_saved').ask('Continue')
    expect(requests.first['previous_response_id']).to eq('resp_saved')
    expect(requests.first['input'].size).to eq(1)
  end

  it 'executes local tools and sends only their results in the chained followup' do
    tool = sample_tool_call_response.merge('output' => [
                                             { 'type' => 'function_call', 'call_id' => 'call_1',
                                               'name' => 'migration_weather',
                                               'arguments' => '{"city":"Warsaw"}' }
                                           ])
    stub_completions(tool, completion('resp_answer', 'Sunny'))
    result = chat.with_tools(MigrationWeather).ask('Weather in Warsaw?')
    expect(result.content).to eq('Sunny')
    expect(requests.last['previous_response_id']).to eq('resp_456')
    expect(requests.last['input']).to eq([
                                           { 'type' => 'function_call_output', 'call_id' => 'call_1',
                                             'output' => 'Sunny in Warsaw' }
                                         ])
  end

  it 'preserves native schema, tool preferences, max tokens, citations and reasoning' do
    stub_completions(completion('resp_schema', '{"answer":"yes"}'))
    chat.with_tools(MigrationWeather).with_tool_options(choice: :required, calls: :one)
        .with_max_output_tokens(100).with_thinking(effort: :low)
        .with_end_user('migration-user').with_caching(key: 'migration-cache')
        .with_schema(type: 'object', properties: { answer: { type: 'string' } }, required: ['answer'])
        .with_provider_options(metadata: { test: 'migration' }).ask('Answer')
    payload = requests.first
    expect(payload['tool_choice']).to eq('required')
    expect(payload['parallel_tool_calls']).to be(false)
    expect(payload['max_output_tokens']).to eq(100)
    expect(payload.dig('reasoning', 'effort')).to eq('low')
    expect(payload.dig('text', 'format', 'type')).to eq('json_schema')
    expect(payload['metadata']).to eq('test' => 'migration')
    expect(payload['safety_identifier']).to eq('migration-user')
    expect(payload['prompt_cache_key']).to eq('migration-cache')
  end

  it 'supports native provider tools and automatic compaction' do
    stub_completions(completion('resp_tools'))
    chat.with_provider_tools(:web_search).with_compaction(at: 100_000).ask('Search')
    expect(requests.first['tools']).to include('type' => 'web_search')
    expect(requests.first['context_management']).to eq([{ 'type' => 'compaction', 'compact_threshold' => 100_000 }])
  end

  it 'leaves native OpenAI stateless, including streaming and server tools' do
    stub_completions(completion('resp_native'))
    native = RubyLLM.chat(model: 'gpt-4o', provider: :openai)
    expect(native.ask('Hello').response_id).to be_nil
    expect(requests.first['store']).to be(false)
    expect(RubyLLM.method(:batch).parameters).to eq([%i[req chats]])
    expect(RubyLLM::Protocols::Responses.ancestors).not_to include(RubyLLM::Providers::OpenAIResponses::Protocol)
  end

  it 'reuses uploaded files through the native Files protocol' do
    stub_completions(completion('resp_file'))
    file = RubyLLM::UploadedFile.new(id: 'file_saved', provider: 'openai_responses',
                                     filename: 'document.pdf', mime_type: 'application/pdf')
    chat.ask('Summarize', with: [file])
    expect(requests.first['input'].first['content']).to include('type' => 'input_file', 'file_id' => 'file_saved')
  end

  it 'retains incomplete response metadata from HTTP streams' do
    body = completion('resp_incomplete', status: 'incomplete', incomplete_details: { 'reason' => 'max_output_tokens' })
    stub_streams(body)
    result = chat.ask('Hello') { |_chunk| }
    expect(result).to be_max_tokens
    expect(result.response_id).to eq('resp_incomplete')
    expect(result.raw.body).to eq(body)
  end

  it 'preserves the native model catalog and serialized message fields' do
    model = chat.model
    expect(model.provider).to eq('openai_responses')
    original = RubyLLM::Message.new(role: :assistant, content: 'Hello', model: 'gpt-4o',
                                    thinking: RubyLLM::Thinking.build(text: 'reason', signature: 'encrypted'))
    restored = RubyLLM::Message.new(original.to_h.merge(response_id: 'resp_saved'))
    expect(restored.response_id).to eq('resp_saved')
    expect(restored.thinking.signature).to eq('encrypted')
    expect(restored.to_h.except(:response_id)).to eq(original.to_h)
  end
end
