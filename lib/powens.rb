# frozen_string_literal: true

require "powens/version"
require "powens/configuration"
require "powens/errors"
require "powens/client"

module Powens
  class << self
    attr_accessor :configuration

    # Configure the Powens client
    #
    # @example
    #   Powens.configure do |config|
    #     config.domain = "my-domain"
    #     config.config_token = "my_config_token"
    #     config.client_id = "my_client_id"
    #     config.client_secret = "my_client_secret"
    #   end
    #
    def configure
      self.configuration ||= Configuration.new
      yield(configuration)
    end

    # Create a new client instance
    #
    # @param user_token [String, nil] Optional user token for authenticated requests
    # @return [Powens::Client]
    #
    # @example Without user token (config token auth)
    #   client = Powens.client
    #   client.list_connectors
    #
    # @example With user token
    #   client = Powens.client(user_token: "permanent_token")
    #   client.list_accounts
    #
    def client(user_token: nil)
      Client.new(user_token: user_token)
    end

    # Reset configuration (useful for testing)
    def reset_configuration!
      self.configuration = nil
    end
  end
end
