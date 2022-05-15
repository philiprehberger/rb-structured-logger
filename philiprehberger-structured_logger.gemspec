# frozen_string_literal: true

require_relative 'lib/philiprehberger/structured_logger/version'

Gem::Specification.new do |spec|
  spec.name = 'philiprehberger-structured_logger'
  spec.version = Philiprehberger::StructuredLogger::VERSION
  spec.authors = ['Philip Rehberger']
  spec.email = ['me@philiprehberger.com']

  spec.summary = 'Structured JSON logger with context and child loggers'
  spec.description = 'A zero-dependency Ruby gem for structured JSON logging with context merging, ' \
                     'child loggers, level filtering, and pluggable outputs.'
  spec.homepage = 'https://github.com/philiprehberger/rb-structured-logger'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"

  spec.files = Dir['lib/**/*.rb', 'LICENSE', 'README.md', 'CHANGELOG.md']

  spec.require_paths = ['lib']
end
