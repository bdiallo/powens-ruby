# frozen_string_literal: true

RSpec.describe Powens::Configuration do
  describe "#initialize" do
    it "sets default values" do
      config = described_class.new

      expect(config.environment).to eq(:sandbox)
      expect(config.timeout).to eq(30)
      expect(config.open_timeout).to eq(10)
    end
  end

  describe "#base_url" do
    it "builds URL from domain" do
      config = described_class.new
      config.domain = "my-company"

      expect(config.base_url).to eq("https://my-company.biapi.pro/2.0")
    end
  end

  describe "#webview_base_url" do
    it "returns the webview URL" do
      config = described_class.new

      expect(config.webview_base_url).to eq("https://webview.powens.com")
    end
  end

  describe "#valid?" do
    it "returns true when domain and config_token are set" do
      config = described_class.new
      config.domain = "test"
      config.config_token = "token123"

      expect(config.valid?).to be true
    end

    it "returns false when domain is missing" do
      config = described_class.new
      config.config_token = "token123"

      expect(config.valid?).to be false
    end

    it "returns false when config_token is missing" do
      config = described_class.new
      config.domain = "test"

      expect(config.valid?).to be false
    end
  end

  describe "#production?" do
    it "returns true when environment is production" do
      config = described_class.new
      config.environment = :production

      expect(config.production?).to be true
      expect(config.sandbox?).to be false
    end
  end

  describe "#sandbox?" do
    it "returns true when environment is sandbox" do
      config = described_class.new
      config.environment = :sandbox

      expect(config.sandbox?).to be true
      expect(config.production?).to be false
    end
  end
end
