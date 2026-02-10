# frozen_string_literal: true

module Powens
  # Base error class for all Powens errors
  class Error < StandardError; end

  # Error raised when API returns an error response
  class ApiError < Error
    attr_reader :status, :body, :error_code

    def initialize(status, body)
      @status = status
      @body = body
      @error_code = extract_error_code(body)
      super(build_message)
    end

    private

    def extract_error_code(body)
      return nil unless body.is_a?(Hash)

      body[:error] || body[:code] || body["error"] || body["code"]
    end

    def build_message
      msg = "Powens API Error (#{status})"
      msg += ": #{error_code}" if error_code
      msg += " - #{body}" if body && !body.empty?
      msg
    end
  end

  # Error raised on 401/403 authentication failures
  class AuthenticationError < ApiError
    def initialize(status, body)
      super
    end
  end

  # Error raised on 404 not found
  class NotFoundError < ApiError
    def initialize(status, body)
      super
    end
  end

  # Error raised on 422 validation errors
  class ValidationError < ApiError
    def initialize(status, body)
      super
    end
  end

  # Error raised on 429 rate limit exceeded
  class RateLimitError < ApiError
    attr_reader :retry_after

    def initialize(status, body, retry_after: nil)
      @retry_after = retry_after
      super(status, body)
    end
  end

  # Error raised on connection failures (timeout, network issues)
  class ConnectionError < Error
    attr_reader :original_error

    def initialize(message, original_error: nil)
      @original_error = original_error
      super(message)
    end
  end

  # Error raised when configuration is missing or invalid
  class ConfigurationError < Error; end

  # Error raised when SCA (Strong Customer Authentication) is required
  class SCARequiredError < ApiError
    def initialize(status, body)
      super
    end

    def requires_webview?
      true
    end
  end
end
