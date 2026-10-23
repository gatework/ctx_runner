# frozen_string_literal: true

require_relative "lib/ctx_runner/version"

Gem::Specification.new do |spec|
  spec.name = "ctx_runner"
  spec.version = CtxRunner::VERSION
  spec.authors = [ "Gatework contributors" ]
  spec.summary = "Run evidence collection and controlled network changes."
  spec.description = "Shared collection, evidence publication and controlled change workflows with explicit ownership and failure evidence."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.6"
  spec.metadata = { "allowed_push_host" => "https://rubygems.org", "rubygems_mfa_required" => "true" }
  # 明确限定发布内容；设备来源、凭据与本地测试产物不进入包。
  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*.rb", "examples/**/*.rb", "docs/**/*.md", "README*.md", "CHANGELOG.md", "LICENSE"].sort }
  spec.require_paths = [ "lib" ]
  spec.add_dependency "ctx_parser", ">= 0.2.7"
  spec.add_dependency "ctx_driver", ">= 0.2.7"
  %w[digest ipaddr json time tempfile fileutils].each { |name| spec.add_dependency name }
end
