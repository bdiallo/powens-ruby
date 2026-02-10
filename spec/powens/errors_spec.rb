# frozen_string_literal: true

RSpec.describe Powens::Error do
  it "is a StandardError" do
    expect(described_class.new).to be_a(StandardError)
  end
end

RSpec.describe Powens::ApiError do
  describe "#initialize" do
    it "stores status and body" do
      error = described_class.new(422, { error: "validation_failed" })

      expect(error.status).to eq(422)
      expect(error.body).to eq({ error: "validation_failed" })
      expect(error.error_code).to eq("validation_failed")
    end

    it "extracts error_code from body" do
      error = described_class.new(400, { code: "invalid_request" })

      expect(error.error_code).to eq("invalid_request")
    end

    it "builds informative message" do
      error = described_class.new(422, { error: "validation_failed" })

      expect(error.message).to include("422")
      expect(error.message).to include("validation_failed")
    end

    it "handles empty body" do
      error = described_class.new(500, {})

      expect(error.status).to eq(500)
      expect(error.error_code).to be_nil
    end
  end
end

RSpec.describe Powens::AuthenticationError do
  it "is an ApiError" do
    error = described_class.new(401, { error: "invalid_token" })

    expect(error).to be_a(Powens::ApiError)
    expect(error.status).to eq(401)
  end
end

RSpec.describe Powens::NotFoundError do
  it "is an ApiError" do
    error = described_class.new(404, { error: "not_found" })

    expect(error).to be_a(Powens::ApiError)
    expect(error.status).to eq(404)
  end
end

RSpec.describe Powens::ValidationError do
  it "is an ApiError" do
    error = described_class.new(422, { error: "invalid_params" })

    expect(error).to be_a(Powens::ApiError)
    expect(error.status).to eq(422)
  end
end

RSpec.describe Powens::RateLimitError do
  it "is an ApiError with retry_after" do
    error = described_class.new(429, { error: "rate_limit" }, retry_after: 60)

    expect(error).to be_a(Powens::ApiError)
    expect(error.status).to eq(429)
    expect(error.retry_after).to eq(60)
  end

  it "handles nil retry_after" do
    error = described_class.new(429, { error: "rate_limit" })

    expect(error.retry_after).to be_nil
  end
end

RSpec.describe Powens::ConnectionError do
  it "stores original error" do
    original = Faraday::TimeoutError.new("timeout")
    error = described_class.new("Connection failed", original_error: original)

    expect(error.message).to eq("Connection failed")
    expect(error.original_error).to eq(original)
  end
end

RSpec.describe Powens::ConfigurationError do
  it "is a Powens::Error" do
    error = described_class.new("Missing configuration")

    expect(error).to be_a(Powens::Error)
    expect(error.message).to eq("Missing configuration")
  end
end

RSpec.describe Powens::SCARequiredError do
  it "is an ApiError" do
    error = described_class.new(403, { error: "SCARequired" })

    expect(error).to be_a(Powens::ApiError)
    expect(error.status).to eq(403)
  end

  it "indicates webview is required" do
    error = described_class.new(403, { error: "SCARequired" })

    expect(error.requires_webview?).to be true
  end
end
