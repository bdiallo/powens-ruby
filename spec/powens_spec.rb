# frozen_string_literal: true

RSpec.describe Powens do
  describe ".configure" do
    it "yields a configuration object" do
      described_class.configure do |config|
        expect(config).to be_a(Powens::Configuration)
      end
    end

    it "stores the configuration" do
      described_class.configure do |config|
        config.domain = "test-domain"
        config.config_token = "test_token"
      end

      expect(described_class.configuration.domain).to eq("test-domain")
      expect(described_class.configuration.config_token).to eq("test_token")
    end

    it "preserves configuration between calls" do
      described_class.configure { |c| c.domain = "first" }
      described_class.configure { |c| c.config_token = "token" }

      expect(described_class.configuration.domain).to eq("first")
      expect(described_class.configuration.config_token).to eq("token")
    end
  end

  describe ".reset_configuration!" do
    it "clears the configuration" do
      described_class.configure { |c| c.domain = "test" }
      described_class.reset_configuration!

      expect(described_class.configuration).to be_nil
    end
  end

  describe ".client" do
    before { configure_powens }

    it "returns a new client" do
      client = described_class.client

      expect(client).to be_a(Powens::Client)
    end

    it "passes user_token to the client" do
      client = described_class.client(user_token: "my_token")

      expect(client.webview_url).to include("my_token")
    end

    it "raises ConfigurationError when not configured" do
      described_class.reset_configuration!

      expect { described_class.client }.to raise_error(Powens::ConfigurationError)
    end
  end
end
