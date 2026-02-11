# frozen_string_literal: true

RSpec.describe Powens::Client do
  before { configure_powens }

  describe "#initialize" do
    it "creates a client without user_token" do
      client = Powens.client

      expect(client).to be_a(described_class)
    end

    it "creates a client with user_token" do
      client = Powens.client(user_token: "my_token")

      expect(client.webview_url).to include("my_token")
    end

    it "raises ConfigurationError when not configured" do
      Powens.reset_configuration!

      expect { Powens.client }.to raise_error(Powens::ConfigurationError)
    end
  end

  describe "#create_user" do
    let(:client) { Powens.client }

    it "creates a temporary user and returns auth token" do
      stub_powens_request(:post, "/auth/init",
        response_body: {
          auth_token: "temp_xxx",
          type: "temporary",
          id_user: 42
        }
      )

      result = client.create_user

      expect(result[:auth_token]).to eq("temp_xxx")
      expect(result[:type]).to eq("temporary")
      expect(result[:id_user]).to eq(42)
    end
  end

  describe "#get_permanent_token" do
    let(:client) { Powens.client }

    it "exchanges temporary token for permanent token" do
      stub_powens_request(:post, "/auth/token/access",
        response_body: {
          token: "perm_yyy",
          type: "permanent"
        }
      )

      result = client.get_permanent_token("temp_xxx")

      expect(result[:token]).to eq("perm_yyy")
      expect(result[:type]).to eq("permanent")
    end
  end

  describe "#create_temporary_code" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "generates a temporary code for webview" do
      stub_powens_request(:get, "/auth/token/code",
        response_body: {
          code: "abc123",
          type: "temporary",
          expires_in: 3600
        }
      )

      result = client.create_temporary_code

      expect(result[:code]).to eq("abc123")
      expect(result[:type]).to eq("temporary")
    end
  end

  describe "#list_connectors" do
    let(:client) { Powens.client }

    it "returns list of available connectors" do
      stub_powens_request(:get, "/connectors",
        response_body: {
          connectors: [
            { id: 1, name: "Crédit Agricole" },
            { id: 2, name: "BNP Paribas" }
          ]
        }
      )

      result = client.list_connectors

      expect(result[:connectors].count).to eq(2)
      expect(result[:connectors].first[:name]).to eq("Crédit Agricole")
    end
  end

  describe "#list_connections" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "returns user connections" do
      stub_powens_request(:get, "/users/me/connections",
        response_body: {
          connections: [
            { id: 100, id_connector: 1, state: nil }
          ]
        }
      )

      result = client.list_connections

      expect(result[:connections].count).to eq(1)
      expect(result[:connections].first[:id]).to eq(100)
    end
  end

  describe "#get_connection" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "returns connection details with error state" do
      stub_powens_request(:get, "/users/me/connections/100",
        response_body: {
          id: 100,
          id_connector: 1,
          error: "SCARequired",
          error_message: "Strong authentication required"
        }
      )

      result = client.get_connection(100)

      expect(result[:id]).to eq(100)
      expect(result[:error]).to eq("SCARequired")
    end
  end

  describe "#delete_connection" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "deletes the connection" do
      stub_request(:delete, api_url("/users/me/connections/100"))
        .to_return(status: 204)

      result = client.delete_connection(100)

      expect(result).to be true
    end
  end

  describe "#list_accounts" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "returns user accounts" do
      stub_powens_request(:get, "/users/me/accounts",
        response_body: {
          accounts: [
            { id: 1000, name: "Compte Courant", balance: 1500.50, type: "checking" },
            { id: 1001, name: "Livret A", balance: 5000.00, type: "savings" }
          ]
        }
      )

      result = client.list_accounts

      expect(result[:accounts].count).to eq(2)
      expect(result[:accounts].first[:name]).to eq("Compte Courant")
      expect(result[:accounts].first[:balance]).to eq(1500.50)
    end
  end

  describe "#list_transactions" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "returns transactions with filters" do
      stub_request(:get, api_url("/users/me/transactions"))
        .with(query: { limit: 50, min_date: "2024-01-01" })
        .to_return(
          status: 200,
          body: {
            transactions: [
              { id: 10001, wording: "CARREFOUR", value: -45.50, date: "2024-01-15" }
            ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.list_transactions(min_date: "2024-01-01")

      expect(result[:transactions].count).to eq(1)
      expect(result[:transactions].first[:wording]).to eq("CARREFOUR")
    end
  end

  describe "#all_transactions" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "fetches all pages of transactions" do
      # First page
      stub_request(:get, api_url("/users/me/transactions"))
        .with(query: { limit: 1000 })
        .to_return(
          status: 200,
          body: {
            transactions: [{ id: 1, wording: "TX1" }],
            _links: { next: { href: "/users/me/transactions?offset=1" } }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      # Second page
      stub_request(:get, api_url("/users/me/transactions?offset=1"))
        .to_return(
          status: 200,
          body: {
            transactions: [{ id: 2, wording: "TX2" }]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.all_transactions

      expect(result.count).to eq(2)
      expect(result.map { |tx| tx[:wording] }).to eq(["TX1", "TX2"])
    end

    it "yields each transaction when block given" do
      stub_request(:get, api_url("/users/me/transactions"))
        .with(query: { limit: 1000 })
        .to_return(
          status: 200,
          body: {
            transactions: [
              { id: 1, wording: "TX1" },
              { id: 2, wording: "TX2" }
            ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      wordings = []
      client.all_transactions { |tx| wordings << tx[:wording] }

      expect(wordings).to eq(["TX1", "TX2"])
    end
  end

  describe "#webview_url" do
    let(:client) { Powens.client(user_token: "my_token") }

    it "generates webview URL with token" do
      url = client.webview_url

      expect(url).to eq("https://webview.powens.com/connect?token=my_token")
    end

    it "includes connector_ids when provided" do
      url = client.webview_url(connector_ids: [1, 2, 3])

      expect(url).to include("connector_ids=1,2,3")
    end
  end

  describe "#webview_reconnect_url" do
    let(:client) { Powens.client(user_token: "my_token") }

    it "generates reconnect URL with connection_id" do
      url = client.webview_reconnect_url(100)

      expect(url).to eq("https://webview.powens.com/reconnect?token=my_token&connection_id=100")
    end
  end

  describe "error handling" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "raises AuthenticationError on 401" do
      stub_powens_request(:get, "/users/me/accounts", status: 401,
        response_body: { error: "invalid_token" })

      expect { client.list_accounts }.to raise_error(Powens::AuthenticationError)
    end

    it "raises SCARequiredError when SCA is needed" do
      stub_powens_request(:get, "/users/me/accounts", status: 403,
        response_body: { error: "SCARequired", error_message: "SCA required" })

      expect { client.list_accounts }.to raise_error(Powens::SCARequiredError)
    end

    it "raises NotFoundError on 404" do
      stub_powens_request(:get, "/users/me/accounts/999", status: 404,
        response_body: { error: "not_found" })

      expect { client.get_account(999) }.to raise_error(Powens::NotFoundError)
    end

    it "raises RateLimitError on 429" do
      stub_request(:get, api_url("/users/me/accounts"))
        .to_return(
          status: 429,
          body: { error: "rate_limit" }.to_json,
          headers: { "Retry-After" => "60" }
        )

      error = nil
      begin
        client.list_accounts
      rescue Powens::RateLimitError => e
        error = e
      end

      expect(error).to be_a(Powens::RateLimitError)
      expect(error.retry_after).to eq(60)
    end

    it "raises ConnectionError on network failure" do
      stub_request(:get, api_url("/users/me/accounts")).to_timeout

      expect { client.list_accounts }.to raise_error(Powens::ConnectionError)
    end
  end

  describe "configuration" do
    it "raises ConfigurationError when not configured" do
      Powens.reset_configuration!

      expect { Powens.client }.to raise_error(Powens::ConfigurationError)
    end
  end

  describe "#get_user" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "returns user information" do
      stub_powens_request(:get, "/users/me",
        response_body: {
          id: 42,
          signin: "user@example.com",
          platform: "web"
        }
      )

      result = client.get_user

      expect(result[:id]).to eq(42)
      expect(result[:signin]).to eq("user@example.com")
    end

    it "accepts a specific user_id" do
      stub_powens_request(:get, "/users/123",
        response_body: { id: 123 }
      )

      result = client.get_user(123)

      expect(result[:id]).to eq(123)
    end
  end

  describe "#delete_user" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "deletes the user" do
      stub_request(:delete, api_url("/users/42"))
        .to_return(status: 204)

      result = client.delete_user(42)

      expect(result).to be true
    end
  end

  describe "#get_connector" do
    let(:client) { Powens.client }

    it "returns connector details" do
      stub_powens_request(:get, "/connectors/1",
        response_body: {
          id: 1,
          name: "Crédit Agricole",
          uuid: "ca-uuid",
          capabilities: ["bank"]
        }
      )

      result = client.get_connector(1)

      expect(result[:id]).to eq(1)
      expect(result[:name]).to eq("Crédit Agricole")
    end
  end

  describe "#sync_connection" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "triggers a sync for the connection" do
      stub_powens_request(:put, "/users/me/connections/100",
        response_body: {
          id: 100,
          state: "syncing",
          last_update: "2024-01-15T10:00:00Z"
        }
      )

      result = client.sync_connection(100)

      expect(result[:id]).to eq(100)
      expect(result[:state]).to eq("syncing")
    end
  end

  describe "#list_accounts with connection_id" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "returns accounts for a specific connection" do
      stub_powens_request(:get, "/users/me/connections/100/accounts",
        response_body: {
          accounts: [
            { id: 1000, name: "Compte Courant", balance: 1500.50 }
          ]
        }
      )

      result = client.list_accounts(connection_id: 100)

      expect(result[:accounts].count).to eq(1)
    end
  end

  describe "#get_account" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "returns account details" do
      stub_powens_request(:get, "/users/me/accounts/1000",
        response_body: {
          id: 1000,
          name: "Compte Courant",
          balance: 1500.50,
          type: "checking",
          currency: "EUR",
          iban: "FR7612345678901234567890123"
        }
      )

      result = client.get_account(1000)

      expect(result[:id]).to eq(1000)
      expect(result[:iban]).to eq("FR7612345678901234567890123")
    end
  end

  describe "#update_account" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "updates account attributes" do
      stub_powens_request(:put, "/users/me/accounts/1000",
        response_body: {
          id: 1000,
          name: "Compte Principal",
          disabled: false
        }
      )

      result = client.update_account(1000, name: "Compte Principal")

      expect(result[:name]).to eq("Compte Principal")
    end
  end

  describe "#get_transaction" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "returns transaction details" do
      stub_powens_request(:get, "/users/me/transactions/10001",
        response_body: {
          id: 10001,
          wording: "CARREFOUR",
          original_wording: "PAIEMENT CB CARREFOUR",
          value: -45.50,
          date: "2024-01-15",
          id_category: 5
        }
      )

      result = client.get_transaction(10001)

      expect(result[:id]).to eq(10001)
      expect(result[:original_wording]).to eq("PAIEMENT CB CARREFOUR")
    end
  end

  describe "#update_transaction" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "updates transaction attributes" do
      stub_powens_request(:put, "/users/me/transactions/10001",
        response_body: {
          id: 10001,
          wording: "Courses",
          id_category: 10
        }
      )

      result = client.update_transaction(10001, wording: "Courses", id_category: 10)

      expect(result[:wording]).to eq("Courses")
    end
  end

  describe "#list_investments" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "returns user investments" do
      stub_powens_request(:get, "/users/me/investments",
        response_body: {
          investments: [
            { id: 5000, label: "Fonds Euro", unitvalue: 100.0, quantity: 50.0 }
          ]
        }
      )

      result = client.list_investments

      expect(result[:investments].count).to eq(1)
      expect(result[:investments].first[:label]).to eq("Fonds Euro")
    end

    it "returns investments for a specific account" do
      stub_powens_request(:get, "/users/me/accounts/1000/investments",
        response_body: {
          investments: [
            { id: 5001, label: "Actions CAC40", unitvalue: 50.0, quantity: 10.0 }
          ]
        }
      )

      result = client.list_investments(account_id: 1000)

      expect(result[:investments].first[:label]).to eq("Actions CAC40")
    end
  end

  describe "#list_market_orders" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "returns market orders" do
      stub_powens_request(:get, "/users/me/market_orders",
        response_body: {
          market_orders: [
            { id: 8000, label: "Achat AAPL", unitprice: 150.0, quantity: 5 }
          ]
        }
      )

      result = client.list_market_orders

      expect(result[:market_orders].count).to eq(1)
    end
  end

  describe "#get_balances" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "returns balance history" do
      stub_powens_request(:get, "/users/me/balances",
        response_body: {
          balances: [
            { date: "2024-01-15", balance: 1500.50 },
            { date: "2024-01-14", balance: 1600.00 }
          ]
        }
      )

      result = client.get_balances

      expect(result[:balances].count).to eq(2)
    end

    it "accepts date filters" do
      stub_request(:get, api_url("/users/me/balances"))
        .with(query: { min_date: "2024-01-01", max_date: "2024-01-31" })
        .to_return(
          status: 200,
          body: { balances: [] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.get_balances(min_date: "2024-01-01", max_date: "2024-01-31")

      expect(result[:balances]).to eq([])
    end
  end

  describe "#list_categories" do
    let(:client) { Powens.client }

    it "returns transaction categories" do
      stub_powens_request(:get, "/categories",
        response_body: {
          categories: [
            { id: 1, name: "Alimentation" },
            { id: 2, name: "Transport" }
          ]
        }
      )

      result = client.list_categories

      expect(result[:categories].count).to eq(2)
    end
  end

  describe "#get_category" do
    let(:client) { Powens.client }

    it "returns category details" do
      stub_powens_request(:get, "/categories/1",
        response_body: {
          id: 1,
          name: "Alimentation",
          parent_id: nil
        }
      )

      result = client.get_category(1)

      expect(result[:name]).to eq("Alimentation")
    end
  end

  describe "#list_account_types" do
    let(:client) { Powens.client }

    it "returns account types" do
      stub_powens_request(:get, "/account_types",
        response_body: {
          account_types: [
            { name: "checking", wording: "Compte courant" },
            { name: "savings", wording: "Compte épargne" }
          ]
        }
      )

      result = client.list_account_types

      expect(result[:account_types].count).to eq(2)
    end
  end

  describe "#list_documents" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "returns user documents" do
      stub_powens_request(:get, "/users/me/documents",
        response_body: {
          documents: [
            { id: 9000, type: "RIB", date: "2024-01-01" }
          ]
        }
      )

      result = client.list_documents

      expect(result[:documents].count).to eq(1)
      expect(result[:documents].first[:type]).to eq("RIB")
    end
  end

  describe "#list_transactions with account_id" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "returns transactions for a specific account" do
      stub_request(:get, api_url("/users/me/accounts/1000/transactions"))
        .with(query: { limit: 50 })
        .to_return(
          status: 200,
          body: {
            transactions: [
              { id: 10001, wording: "TX1", value: -10.0 }
            ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.list_transactions(account_id: 1000)

      expect(result[:transactions].count).to eq(1)
    end
  end

  describe "#list_transactions with all filters" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "applies all filters" do
      stub_request(:get, api_url("/users/me/transactions"))
        .with(query: {
          limit: 100,
          min_date: "2024-01-01",
          max_date: "2024-01-31",
          income: true,
          expand: "categories"
        })
        .to_return(
          status: 200,
          body: { transactions: [] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.list_transactions(
        limit: 100,
        min_date: "2024-01-01",
        max_date: "2024-01-31",
        income: true,
        expand: "categories"
      )

      expect(result[:transactions]).to eq([])
    end
  end

  describe "error handling edge cases" do
    let(:client) { Powens.client(user_token: "perm_token") }

    it "raises AuthenticationError on 403 without SCARequired" do
      stub_powens_request(:get, "/users/me/accounts", status: 403,
        response_body: { error: "forbidden" })

      expect { client.list_accounts }.to raise_error(Powens::AuthenticationError)
    end

    it "raises ValidationError on 422" do
      stub_powens_request(:put, "/users/me/accounts/1000", status: 422,
        response_body: { error: "invalid_params", message: "Name is required" })

      expect { client.update_account(1000, name: "") }.to raise_error(Powens::ValidationError)
    end

    it "raises ApiError on 500" do
      stub_powens_request(:get, "/users/me/accounts", status: 500,
        response_body: { error: "internal_error" })

      expect { client.list_accounts }.to raise_error(Powens::ApiError)
    end

    it "raises ConnectionError on connection failure" do
      stub_request(:get, api_url("/users/me/accounts"))
        .to_raise(Faraday::ConnectionFailed.new("Connection refused"))

      expect { client.list_accounts }.to raise_error(Powens::ConnectionError)
    end
  end
end
