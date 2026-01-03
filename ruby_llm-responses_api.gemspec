# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = 'ruby_llm-responses_api'
  spec.version = '0.1.0'
  spec.authors = ['Chris Hasinski']
  spec.email = ['krzysztof.hasinski@gmail.com']

  spec.summary = 'OpenAI Responses API provider for RubyLLM'
  spec.description = 'A RubyLLM provider that implements OpenAI\'s Responses API, ' \
                     'providing access to built-in tools (web search, code interpreter, ' \
                     'file search), stateful conversations, background mode, and MCP support.'
  spec.homepage = 'https://github.com/khasinski/ruby_llm-responses_api'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.glob('{lib}/**/*') + %w[README.md LICENSE.txt CHANGELOG.md]
  spec.require_paths = ['lib']

  spec.add_dependency 'ruby_llm', '>= 1.0'

  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 1.0'
  spec.add_development_dependency 'vcr', '~> 6.0'
  spec.add_development_dependency 'webmock', '~> 3.0'
end
