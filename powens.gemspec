# frozen_string_literal: true

require_relative "lib/powens/version"

Gem::Specification.new do |spec|
  spec.name          = "powens"
  spec.version       = Powens::VERSION
  spec.authors       = ["Boubacar Diallo"]
  spec.email         = ["boubacar@jamaa.co"]

  spec.summary       = "Ruby client for Powens Open Banking API"
  spec.description   = "A Ruby gem for integrating with the Powens (formerly Budget Insight) Open Banking API. " \
                       "Supports account aggregation, transaction syncing, and SCA authentication flows."
  spec.homepage      = "https://github.com/bdiallo/powens-ruby"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["lib/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", ">= 1.0", "< 3.0"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "webmock", "~> 3.18"
end
