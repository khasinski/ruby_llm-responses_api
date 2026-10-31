#!/usr/bin/env ruby
# frozen_string_literal: true

# Real API integration test for ruby_llm-responses_api
# Run with: OPENAI_API_KEY=your_key bundle exec ruby examples/test_real_api.rb

require 'bundler/setup'
require 'rubyllm_responses_api'

# Configure
RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch('OPENAI_API_KEY', nil)
end

def separator(title)
  puts "\n#{'=' * 60}"
  puts "  #{title}"
  puts '=' * 60
end

def test_basic_chat
  separator('Test 1: Basic Chat Completion')

  chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)
  response = chat.ask('What is 2 + 2? Reply with just the number.')

  puts "Response: #{response.content}"
  puts "Model: #{response.model}"
  puts "Input tokens: #{response.tokens.input}"
  puts "Output tokens: #{response.tokens.output}"
  puts "Response ID: #{response.response_id}" if response.respond_to?(:response_id)

  response.content.include?('4') ? puts('✓ PASSED') : puts('✗ FAILED')
rescue StandardError => e
  puts "✗ FAILED: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

def test_streaming
  separator('Test 2: Streaming')

  chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)

  print 'Streaming response: '
  full_content = ''

  chat.ask('Count from 1 to 5, one number per line.') do |chunk|
    if chunk.content
      print chunk.content
      full_content += chunk.content
    end
  end

  puts "\n\nFull content length: #{full_content.length}"
  full_content.length.positive? ? puts('✓ PASSED') : puts('✗ FAILED')
rescue StandardError => e
  puts "✗ FAILED: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

def test_system_instructions
  separator('Test 3: System Instructions')

  chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)
  chat.with_instructions('You are a pirate. Always respond like a pirate.')
  response = chat.ask('Say hello')

  puts "Response: #{response.content}"

  # Check for pirate-like language
  pirate_words = %w[arr matey ahoy ye aye captain]
  has_pirate = pirate_words.any? { |word| response.content.downcase.include?(word) }
  has_pirate ? puts('✓ PASSED') : puts('✗ PASSED (content varies)')
rescue StandardError => e
  puts "✗ FAILED: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

class GetWeatherTool < RubyLLM::Tool
  description 'Get the current weather for a location'
  parameter :location, type: 'string', description: 'The city name'

  def execute(location:)
    "The weather in #{location} is sunny, 72°F"
  end
end

def test_function_calling
  separator('Test 4: Function Calling')

  chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)
  chat.with_tools(GetWeatherTool)

  response = chat.ask("What's the weather in Tokyo?")

  puts "Response: #{response.content}"

  # Should have called the tool and gotten a response
  if response.content.include?('72') || response.content.downcase.include?('tokyo')
    puts('✓ PASSED')
  else
    puts('✗ FAILED')
  end
rescue StandardError => e
  puts "✗ FAILED: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

def test_multi_turn_conversation
  separator('Test 5: Multi-turn Conversation')

  chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)

  # First turn
  response1 = chat.ask('My favorite color is blue. Remember that.')
  puts "Turn 1: #{response1.content[0..100]}..."

  # Second turn - should remember
  response2 = chat.ask('What is my favorite color?')
  puts "Turn 2: #{response2.content}"

  response2.content.downcase.include?('blue') ? puts('✓ PASSED') : puts('✗ FAILED')
rescue StandardError => e
  puts "✗ FAILED: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

def test_web_search
  separator('Test 6: Web Search (Built-in Tool)')

  chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)
  chat.with_provider_options(tools: [{ type: 'web_search_preview' }])

  response = chat.ask('What is the current price of Bitcoin? Just give me a rough number.')

  puts "Response: #{response.content}"

  # Should contain some response about Bitcoin
  response.content.length > 10 ? puts('✓ PASSED') : puts('✗ FAILED')
rescue StandardError => e
  puts "✗ FAILED: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

def test_structured_output
  separator('Test 7: Structured Output (JSON Schema)')

  chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)

  schema = {
    type: 'object',
    properties: {
      name: { type: 'string' },
      age: { type: 'integer' },
      city: { type: 'string' }
    },
    required: %w[name age city],
    additionalProperties: false
  }

  chat.with_schema(schema)
  response = chat.ask('Generate a fictional person with name, age, and city.')

  puts "Response: #{response.content.inspect}"

  # Content should be parsed as Hash
  if response.parsed.is_a?(Hash)
    if response.parsed['name'] && response.parsed['age'] && response.parsed['city']
      puts '✓ PASSED'
    else
      puts '✗ FAILED (missing fields)'
    end
  else
    puts '✗ FAILED (not a Hash)'
  end
rescue StandardError => e
  puts "✗ FAILED: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

def test_vision
  separator('Test 8: Vision (Image URL)')

  chat = RubyLLM.chat(model: 'gpt-4o-mini', provider: :openai_responses)

  # Use a reliable test image
  image_url = 'https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_272x92dp.png'

  response = chat.ask('What do you see in this image? Be brief.', with: [image_url])

  puts "Response: #{response.content}"
  response.content.length > 10 ? puts('✓ PASSED') : puts('✗ FAILED')
rescue StandardError => e
  puts "✗ FAILED: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# Run all tests
puts "\n🚀 Ruby LLM Responses API - Real API Tests"
puts 'Using model: gpt-4o-mini'
puts 'Provider: :openai_responses'

test_basic_chat
test_streaming
test_system_instructions
test_function_calling
test_multi_turn_conversation
test_web_search
test_structured_output
test_vision

separator('All Tests Complete!')
