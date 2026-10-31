# frozen_string_literal: true

source 'https://rubygems.org'

gemspec name: 'ruby_llm-responses_api'

# Use local ruby_llm source for development only when explicitly requested.
if ENV['RUBY_LLM_SOURCE'] && File.exist?(File.join(__dir__, 'ruby_llm_source'))
  gem 'ruby_llm', ENV.fetch('RUBY_LLM_VERSION', '~> 2.1.1'), path: './ruby_llm_source'
else
  gem 'ruby_llm', ENV.fetch('RUBY_LLM_VERSION', '~> 2.1.1')
end

group :development, :test do
  gem 'dotenv'
  gem 'pry'
end
