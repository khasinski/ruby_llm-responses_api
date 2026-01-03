# frozen_string_literal: true

source 'https://rubygems.org'

gemspec name: 'ruby_llm-responses_api'

# Use local ruby_llm source for development if available, otherwise use gem
if File.exist?(File.join(__dir__, 'ruby_llm_source'))
  gem 'ruby_llm', path: './ruby_llm_source'
else
  gem 'ruby_llm'
end

group :development, :test do
  gem 'dotenv'
  gem 'pry'
end
