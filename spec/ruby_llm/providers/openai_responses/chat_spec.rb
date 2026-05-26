# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::OpenAIResponses::Chat do
  let(:chat_module) { RubyLLM::Providers::OpenAIResponses::Chat }
  let(:model) { instance_double(RubyLLM::Model::Info, id: 'gpt-4o') }

  describe '.render_payload' do
    let(:user_message) do
      RubyLLM::Message.new(role: :user, content: 'Hello')
    end

    let(:system_message) do
      RubyLLM::Message.new(role: :system, content: 'You are a helpful assistant')
    end

    it 'creates basic payload with model and input' do
      payload = chat_module.render_payload(
        [user_message],
        tools: {},
        temperature: nil,
        model: model,
        stream: false
      )

      expect(payload[:model]).to eq('gpt-4o')
      expect(payload[:input]).to be_an(Array)
      expect(payload[:stream]).to be false
    end

    it 'extracts system messages to instructions' do
      payload = chat_module.render_payload(
        [system_message, user_message],
        tools: {},
        temperature: nil,
        model: model,
        stream: false
      )

      expect(payload[:instructions]).to eq('You are a helpful assistant')
      expect(payload[:input].length).to eq(1)
    end

    it 'embeds files as text or base64' do
      attachments = [
        Pathname.new('./spec/fixtures/ruby.png'),
        Pathname.new('./spec/fixtures/sample.pdf'),
        Pathname.new('./spec/fixtures/ruby.mp3'),
        Pathname.new('./spec/fixtures/ruby.txt')
      ]

      content_with_attachments = RubyLLM::Content.new 'My content with attachments', attachments
      user_message_with_content = RubyLLM::Message.new role: :user, content: content_with_attachments

      payload = chat_module.render_payload(
        [user_message_with_content],
        tools: {},
        temperature: nil,
        model: model,
        stream: false
      )

      actual_input = payload[:input]
      expect(actual_input.length).to eq(1)

      actual_content = actual_input.first[:content]
      expect(actual_content.length).to eq(5)

      expect(actual_content[0]).to eq({ type: 'input_text', text: 'My content with attachments' })

      expect(actual_content[1][:type]).to eq('input_image')
      expect(actual_content[1][:image_url]).to start_with('data:image/png;base64,')

      expect(actual_content[2][:type]).to eq('input_file')
      expect(actual_content[2][:filename]).to start_with('sample.pdf')
      expect(actual_content[2][:file_data]).to start_with('data:application/pdf;base64,')

      expect(actual_content[3][:type]).to eq('input_audio')
      expect(actual_content[3][:data]).to start_with('data:audio/mpeg;base64,')

      expect(actual_content[4]).to eq(
        {
          type: 'input_text',
          text: "<file name='ruby.txt' mime_type='text/plain'>Ruby is the best.</file>"
        }
      )
    end

    it 'rejects unknown attachments' do
      content_with_attachment = RubyLLM::Content.new 'Binary', Pathname.new('./spec/fixtures/sample.bin')
      user_message_with_content = RubyLLM::Message.new role: :user, content: content_with_attachment

      expect do
        chat_module.render_payload(
          [user_message_with_content],
          tools: {},
          temperature: nil,
          model: model,
          stream: false
        )
      end.to raise_exception(RubyLLM::UnsupportedAttachmentError)
    end

    context 'with previous_response_id chain' do
      it 'sends only the new user message in input, not the full history' do
        first_user = RubyLLM::Message.new(role: :user, content: 'Hello')
        first_assistant = RubyLLM::Message.new(
          role: :assistant, content: 'Hi there!', response_id: 'resp_abc123'
        )
        second_user = RubyLLM::Message.new(role: :user, content: 'And your name?')

        payload = chat_module.render_payload(
          [first_user, first_assistant, second_user],
          tools: {}, temperature: nil, model: model, stream: false
        )

        expect(payload[:previous_response_id]).to eq('resp_abc123')
        expect(payload[:input].length).to eq(1)
        expect(payload[:input].first[:content]).to eq('And your name?')
      end

      it 'includes tool results that came after the chained assistant turn' do
        first_user = RubyLLM::Message.new(role: :user, content: 'What is the weather?')
        assistant_with_calls = RubyLLM::Message.new(
          role: :assistant,
          content: nil,
          tool_calls: {
            'call_1' => RubyLLM::ToolCall.new(id: 'call_1', name: 'get_weather', arguments: {})
          },
          response_id: 'resp_xyz'
        )
        tool_result = RubyLLM::Message.new(
          role: :tool, content: '{"temp": 72}', tool_call_id: 'call_1'
        )

        payload = chat_module.render_payload(
          [first_user, assistant_with_calls, tool_result],
          tools: {}, temperature: nil, model: model, stream: false
        )

        expect(payload[:previous_response_id]).to eq('resp_xyz')
        expect(payload[:input].length).to eq(1)
        expect(payload[:input].first[:type]).to eq('function_call_output')
        expect(payload[:input].first[:call_id]).to eq('call_1')
      end

      it 'sends full history when no assistant response_id is present' do
        first_user = RubyLLM::Message.new(role: :user, content: 'Hello')
        first_assistant = RubyLLM::Message.new(role: :assistant, content: 'Hi!')
        second_user = RubyLLM::Message.new(role: :user, content: 'How are you?')

        payload = chat_module.render_payload(
          [first_user, first_assistant, second_user],
          tools: {}, temperature: nil, model: model, stream: false
        )

        expect(payload).not_to have_key(:previous_response_id)
        expect(payload[:input].length).to eq(3)
      end

      it 'anchors on the most recent assistant response_id across many turns' do
        msgs = [
          RubyLLM::Message.new(role: :user, content: 'Turn 1'),
          RubyLLM::Message.new(role: :assistant, content: 'Reply 1', response_id: 'resp_1'),
          RubyLLM::Message.new(role: :user, content: 'Turn 2'),
          RubyLLM::Message.new(role: :assistant, content: 'Reply 2', response_id: 'resp_2'),
          RubyLLM::Message.new(role: :user, content: 'Turn 3')
        ]

        payload = chat_module.render_payload(
          msgs, tools: {}, temperature: nil, model: model, stream: false
        )

        expect(payload[:previous_response_id]).to eq('resp_2')
        expect(payload[:input].length).to eq(1)
        expect(payload[:input].first[:content]).to eq('Turn 3')
      end
    end

    it 'includes temperature when provided' do
      payload = chat_module.render_payload(
        [user_message],
        tools: {},
        temperature: 0.7,
        model: model,
        stream: false
      )

      expect(payload[:temperature]).to eq(0.7)
    end

    context 'with tool_prefs' do
      let(:tool) do
        instance_double(RubyLLM::Tool, name: 'get_weather', description: 'Get weather',
                                       parameters: [], params_schema: nil)
      end
      let(:tools) { { get_weather: tool } }

      before do
        allow(RubyLLM::Providers::OpenAIResponses::Tools)
          .to receive(:tool_for).and_return({ type: 'function', name: 'get_weather' })
      end

      it 'includes tool_choice when choice is set' do
        payload = chat_module.render_payload(
          [user_message], tools: tools, temperature: nil, model: model,
                          tool_prefs: { choice: :required, calls: nil }
        )

        expect(payload[:tool_choice]).to eq('required')
      end

      it 'includes parallel_tool_calls when calls is :many' do
        payload = chat_module.render_payload(
          [user_message], tools: tools, temperature: nil, model: model,
                          tool_prefs: { choice: nil, calls: :many }
        )

        expect(payload[:parallel_tool_calls]).to be true
      end

      it 'sets parallel_tool_calls false when calls is :one' do
        payload = chat_module.render_payload(
          [user_message], tools: tools, temperature: nil, model: model,
                          tool_prefs: { choice: nil, calls: :one }
        )

        expect(payload[:parallel_tool_calls]).to be false
      end

      it 'formats specific function choice correctly' do
        payload = chat_module.render_payload(
          [user_message], tools: tools, temperature: nil, model: model,
                          tool_prefs: { choice: :get_weather, calls: nil }
        )

        expect(payload[:tool_choice]).to eq({ type: 'function', name: 'get_weather' })
      end

      it 'omits tool_choice and parallel_tool_calls when nil' do
        payload = chat_module.render_payload(
          [user_message], tools: tools, temperature: nil, model: model,
                          tool_prefs: { choice: nil, calls: nil }
        )

        expect(payload).not_to have_key(:tool_choice)
        expect(payload).not_to have_key(:parallel_tool_calls)
      end
    end
  end

  describe '.parse_completion_response' do
    it 'parses a successful response' do
      response = mock_response(sample_completion_response)
      message = chat_module.parse_completion_response(response)

      expect(message.role).to eq(:assistant)
      expect(message.content).to eq('Hello! How can I help you today?')
      expect(message.input_tokens).to eq(10)
      expect(message.output_tokens).to eq(8)
    end

    it 'extracts tool calls from function_call outputs' do
      response = mock_response(sample_tool_call_response)
      message = chat_module.parse_completion_response(response)

      expect(message.tool_calls).to be_a(Hash)
      expect(message.tool_calls['call_abc123'].name).to eq('get_weather')
      expect(message.tool_calls['call_abc123'].arguments).to eq({ 'location' => 'San Francisco' })
    end
  end

  describe '.format_input' do
    it 'formats user messages correctly' do
      messages = [RubyLLM::Message.new(role: :user, content: 'Test message')]
      input = chat_module.format_input(messages)

      expect(input.first[:type]).to eq('message')
      expect(input.first[:role]).to eq('user')
      expect(input.first[:content]).to eq('Test message')
    end

    it 'formats tool result messages as function_call_output' do
      messages = [
        RubyLLM::Message.new(
          role: :tool,
          content: '{"result": "success"}',
          tool_call_id: 'call_123'
        )
      ]
      input = chat_module.format_input(messages)

      expect(input.first[:type]).to eq('function_call_output')
      expect(input.first[:call_id]).to eq('call_123')
      expect(input.first[:output]).to eq('{"result": "success"}')
    end
  end
end
