# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = 'ruby_llm-responses_api'
  spec.version = '0.6.1'
  spec.authors = ['Chris Hasinski']
  spec.email = ['krzysztof.hasinski@gmail.com']

  spec.summary = 'Advanced OpenAI Responses API extensions for RubyLLM'
  spec.description = 'RubyLLM extensions for the native OpenAI Responses API protocol, ' \
                     'providing built-in tool helpers, stateful response chaining, ' \
                     'server-side compaction, containers API, background mode, batches, ' \
                     'WebSocket transport, and MCP support.'
  spec.homepage = 'https://github.com/khasinski/ruby_llm-responses_api'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.glob('{lib}/**/*') + %w[README.md LICENSE.txt CHANGELOG.md]
  spec.require_paths = ['lib']

  spec.add_dependency 'ruby_llm', '>= 1.13'

  spec.add_development_dependency 'activerecord', '~> 7.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 1.0'
  spec.add_development_dependency 'sqlite3', '~> 1.4'
  spec.add_development_dependency 'vcr', '~> 6.0'
  spec.add_development_dependency 'webmock', '~> 3.0'
  spec.add_development_dependency 'websocket-client-simple', '~> 0.8'
end
