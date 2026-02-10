# frozen_string_literal: true

module Powens
  # Configuration for the Powens client
  #
  # @example
  #   Powens.configure do |config|
  #     config.domain = "my-domain"           # Your Powens domain (e.g., "jamaa-sandbox")
  #     config.config_token = "xxx"           # Config token from Powens Console
  #     config.client_id = "xxx"              # Client ID from Powens Console
  #     config.client_secret = "xxx"          # Client secret from Powens Console
  #     config.environment = :sandbox         # :sandbox or :production
  #     config.timeout = 30                   # Request timeout in seconds
  #     config.open_timeout = 10              # Connection timeout in seconds
  #   end
  #
  class Configuration
    attr_accessor :domain, :client_id, :client_secret, :config_token,
                  :environment, :timeout, :open_timeout

    def initialize
      @environment = :sandbox
      @timeout = 30
      @open_timeout = 10
    end

    # Base URL for API requests
    # @return [String]
    def base_url
      "https://#{domain}.biapi.pro/2.0"
    end

    # Base URL for webview (bank connection UI)
    # @return [String]
    def webview_base_url
      "https://webview.powens.com"
    end

    # Check if configuration is valid
    # @return [Boolean]
    def valid?
      !domain.nil? && !domain.empty? && !config_token.nil? && !config_token.empty?
    end

    # Check if in production mode
    # @return [Boolean]
    def production?
      environment == :production
    end

    # Check if in sandbox mode
    # @return [Boolean]
    def sandbox?
      environment == :sandbox
    end
  end
end
