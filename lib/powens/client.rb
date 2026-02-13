# frozen_string_literal: true

require "faraday"
require "json"
require "cgi"

module Powens
  # Main API client for Powens Open Banking API
  #
  # @example Basic usage with config token
  #   client = Powens.client
  #   connectors = client.list_connectors
  #
  # @example Usage with user token
  #   client = Powens.client(user_token: "permanent_token")
  #   accounts = client.list_accounts
  #
  class Client
    def initialize(user_token: nil)
      @user_token = user_token
      @config = Powens.configuration || raise(ConfigurationError, "Powens not configured. Call Powens.configure first.")
      @conn = build_connection
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Authentication / Users
    # ═══════════════════════════════════════════════════════════════════════════

    # Create a temporary user and get a temporary token
    # This is the first step in the OAuth flow
    #
    # @return [Hash] { auth_token:, type: "temporary", id_user: }
    def create_user
      post("auth/init", {}, auth_type: :config)
    end

    # Exchange a temporary token for a permanent access token
    # Call this after create_user to get a persistent token
    #
    # @param temporary_token [String] The temporary auth_token from create_user
    # @return [Hash] { token:, type: "permanent" }
    def get_permanent_token(temporary_token)
      # Powens requires client credentials in the body for this endpoint
      body = {
        client_id: @config.client_id,
        client_secret: @config.client_secret
      }
      post("auth/token/access", body, auth_type: :bearer, token: temporary_token)
    end

    # Generate a temporary code for the webview
    # This code is used in the webview URL to authenticate the user
    #
    # @return [Hash] { code:, type: "temporary", expires_in: }
    def create_temporary_code
      get("auth/token/code")
    end

    # Get user information
    #
    # @param user_id [String, Integer] User ID or "me" for current user
    # @return [Hash] User data
    def get_user(user_id = "me")
      get("users/#{user_id}")
    end

    # Delete a user and all associated data
    # This revokes all connections and removes the user from Powens
    #
    # @param user_id [String, Integer] User ID
    # @return [Boolean] true if successful
    def delete_user(user_id)
      delete("users/#{user_id}")
    end

    # Renew a permanent token for an existing user
    # Use this when the current token is invalid/lost but you have the user ID
    # This does NOT require the old token - uses client credentials
    #
    # @param user_id [String, Integer] The Powens user ID (external_user_id)
    # @param revoke_previous [Boolean] Whether to revoke previous tokens (default: true)
    # @return [Hash] { access_token:, token_type: "Bearer" }
    def renew_token(user_id, revoke_previous: true)
      body = {
        grant_type: "client_credentials",
        client_id: @config.client_id,
        client_secret: @config.client_secret,
        id_user: user_id.to_i,
        revoke_previous: revoke_previous
      }
      post("auth/renew", body, auth_type: :none)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Webview URLs
    # ═══════════════════════════════════════════════════════════════════════════

    # Generate URL for the connection webview
    # The webview handles bank selection, credentials, and SCA
    #
    # @param token [String, nil] User token (uses @user_token if not provided)
    # @param connector_ids [Array<Integer>, nil] Optional list of connector IDs to filter
    # @return [String] The webview URL
    def webview_url(token: nil, connector_ids: nil)
      t = token || @user_token
      url = "#{@config.webview_base_url}/connect?token=#{t}"
      url += "&connector_ids=#{connector_ids.join(',')}" if connector_ids&.any?
      url
    end

    # Generate URL for reconnecting an existing connection
    # Use this when SCA is required or credentials have changed
    #
    # @param connection_id [Integer] The Powens connection ID
    # @param token [String, nil] User token
    # @return [String] The reconnect webview URL
    def webview_reconnect_url(connection_id, token: nil)
      t = token || @user_token
      "#{@config.webview_base_url}/reconnect?token=#{t}&connection_id=#{connection_id}"
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Connectors (Banks / Providers)
    # ═══════════════════════════════════════════════════════════════════════════

    # List all available connectors (banks, brokers, etc.)
    #
    # @param expand [String, nil] "fields" to include connector capabilities
    # @return [Hash] { connectors: [...] }
    def list_connectors(expand: nil)
      params = {}
      params[:expand] = expand if expand
      get("connectors", params, auth_type: :config)
    end

    # Get a specific connector
    #
    # @param connector_id [Integer] Connector ID
    # @return [Hash] Connector data
    def get_connector(connector_id)
      get("connectors/#{connector_id}", {}, auth_type: :config)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Connections (User bank links)
    # ═══════════════════════════════════════════════════════════════════════════

    # List all connections for a user
    #
    # @param user_id [String, Integer] User ID or "me"
    # @return [Hash] { connections: [...] }
    def list_connections(user_id: "me")
      get("users/#{user_id}/connections")
    end

    # Get a specific connection
    #
    # @param connection_id [Integer] Connection ID
    # @param user_id [String, Integer] User ID or "me"
    # @return [Hash] Connection data with status, error info, etc.
    def get_connection(connection_id, user_id: "me")
      get("users/#{user_id}/connections/#{connection_id}")
    end

    # Trigger a manual sync for a connection
    #
    # @param connection_id [Integer] Connection ID
    # @param user_id [String, Integer] User ID or "me"
    # @return [Hash] Updated connection data
    def sync_connection(connection_id, user_id: "me")
      put("users/#{user_id}/connections/#{connection_id}", {})
    end

    # Delete a connection (revoke bank link)
    #
    # @param connection_id [Integer] Connection ID
    # @param user_id [String, Integer] User ID or "me"
    # @return [Boolean] true if successful
    def delete_connection(connection_id, user_id: "me")
      delete("users/#{user_id}/connections/#{connection_id}")
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Accounts
    # ═══════════════════════════════════════════════════════════════════════════

    # List all bank accounts for a user
    #
    # @param user_id [String, Integer] User ID or "me"
    # @param connection_id [Integer, nil] Filter by connection
    # @param expand [String, nil] Fields to expand (e.g., "connection.connector" for bank info)
    # @return [Hash] { accounts: [...] }
    def list_accounts(user_id: "me", connection_id: nil, expand: nil)
      path = if connection_id
               "users/#{user_id}/connections/#{connection_id}/accounts"
             else
               "users/#{user_id}/accounts"
             end
      params = {}
      params[:expand] = expand if expand
      get(path, params)
    end

    # Get a specific account
    #
    # @param account_id [Integer] Account ID
    # @param user_id [String, Integer] User ID or "me"
    # @return [Hash] Account data
    def get_account(account_id, user_id: "me")
      get("users/#{user_id}/accounts/#{account_id}")
    end

    # Update account settings (e.g., enable/disable sync)
    #
    # @param account_id [Integer] Account ID
    # @param user_id [String, Integer] User ID or "me"
    # @param attrs [Hash] Attributes to update
    # @return [Hash] Updated account data
    def update_account(account_id, user_id: "me", **attrs)
      put("users/#{user_id}/accounts/#{account_id}", attrs)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Transactions
    # ═══════════════════════════════════════════════════════════════════════════

    # List transactions with filters
    #
    # @param user_id [String, Integer] User ID or "me"
    # @param limit [Integer] Max transactions to return (max 1000)
    # @param min_date [Date, String, nil] Start date filter
    # @param max_date [Date, String, nil] End date filter
    # @param income [Boolean, nil] true for income only, false for expenses only
    # @param account_id [Integer, nil] Filter by account
    # @param expand [String, nil] "categories" to include category details
    # @return [Hash] { transactions: [...], _links: { next: } }
    def list_transactions(user_id: "me", limit: 50, min_date: nil, max_date: nil,
                          income: nil, account_id: nil, expand: nil)
      params = { limit: [limit, 1000].min }
      params[:min_date] = min_date.to_s if min_date
      params[:max_date] = max_date.to_s if max_date
      params[:income] = income unless income.nil?
      params[:expand] = expand if expand

      path = if account_id
               "users/#{user_id}/accounts/#{account_id}/transactions"
             else
               "users/#{user_id}/transactions"
             end

      get(path, params)
    end

    # Get a single transaction
    #
    # @param transaction_id [Integer] Transaction ID
    # @param user_id [String, Integer] User ID or "me"
    # @return [Hash] Transaction data
    def get_transaction(transaction_id, user_id: "me")
      get("users/#{user_id}/transactions/#{transaction_id}")
    end

    # Update transaction metadata (e.g., custom category)
    #
    # @param transaction_id [Integer] Transaction ID
    # @param user_id [String, Integer] User ID or "me"
    # @param attrs [Hash] Attributes to update
    # @return [Hash] Updated transaction data
    def update_transaction(transaction_id, user_id: "me", **attrs)
      put("users/#{user_id}/transactions/#{transaction_id}", attrs)
    end

    # Fetch ALL transactions with automatic pagination
    # Powens uses cursor-based pagination via _links.next
    #
    # @example Collect all transactions
    #   transactions = client.all_transactions(min_date: 30.days.ago)
    #
    # @example Stream processing (memory efficient for large datasets)
    #   client.all_transactions(min_date: 30.days.ago) do |tx|
    #     BankTransaction.create_from_powens!(tx)
    #   end
    #
    # @yield [Hash] Each transaction if block given
    # @return [Array<Hash>, nil] All transactions if no block given
    def all_transactions(user_id: "me", min_date: nil, max_date: nil,
                         income: nil, account_id: nil, expand: nil, &block)
      all = []
      result = list_transactions(
        user_id: user_id, limit: 1000, min_date: min_date, max_date: max_date,
        income: income, account_id: account_id, expand: expand
      )

      loop do
        transactions = result[:transactions] || []
        break if transactions.empty?

        if block_given?
          transactions.each { |tx| yield tx }
        else
          all.concat(transactions)
        end

        next_href = result.dig(:_links, :next, :href)
        break unless next_href

        result = get_raw(next_href)
      end

      block_given? ? nil : all
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Investments (Wealth Aggregation)
    # ═══════════════════════════════════════════════════════════════════════════

    # List investment positions (PEA, Assurance-Vie, etc.)
    #
    # @param user_id [String, Integer] User ID or "me"
    # @param account_id [Integer, nil] Filter by account
    # @return [Hash] { investments: [...] }
    def list_investments(user_id: "me", account_id: nil)
      path = if account_id
               "users/#{user_id}/accounts/#{account_id}/investments"
             else
               "users/#{user_id}/investments"
             end
      get(path)
    end

    # List market orders
    #
    # @param user_id [String, Integer] User ID or "me"
    # @return [Hash] { market_orders: [...] }
    def list_market_orders(user_id: "me")
      get("users/#{user_id}/market_orders")
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Balances
    # ═══════════════════════════════════════════════════════════════════════════

    # Get aggregated balance history
    #
    # @param user_id [String, Integer] User ID or "me"
    # @param min_date [Date, String, nil] Start date
    # @param max_date [Date, String, nil] End date
    # @return [Hash] { balances: [...] }
    def get_balances(user_id: "me", min_date: nil, max_date: nil)
      params = {}
      params[:min_date] = min_date.to_s if min_date
      params[:max_date] = max_date.to_s if max_date
      get("users/#{user_id}/balances", params)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Categories
    # ═══════════════════════════════════════════════════════════════════════════

    # List all transaction categories
    #
    # @return [Hash] { categories: [...] }
    def list_categories
      get("categories", {}, auth_type: :config)
    end

    # Get a specific category
    #
    # @param category_id [Integer] Category ID
    # @return [Hash] Category data
    def get_category(category_id)
      get("categories/#{category_id}", {}, auth_type: :config)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Account Types
    # ═══════════════════════════════════════════════════════════════════════════

    # List all account types
    #
    # @return [Hash] { account_types: [...] }
    def list_account_types
      get("account_types", {}, auth_type: :config)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Documents
    # ═══════════════════════════════════════════════════════════════════════════

    # List documents (bank statements, etc.)
    #
    # @param user_id [String, Integer] User ID or "me"
    # @return [Hash] { documents: [...] }
    def list_documents(user_id: "me")
      get("users/#{user_id}/documents")
    end

    # Download a document file
    #
    # @param document_id [Integer] Document ID
    # @param user_id [String, Integer] User ID or "me"
    # @return [String] Binary file content
    def download_document(document_id, user_id: "me")
      get("users/#{user_id}/documents/#{document_id}/file", {}, raw: true)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Raw request (for pagination)
    # ═══════════════════════════════════════════════════════════════════════════

    # Make a raw GET request to a relative path (used for pagination)
    #
    # @param uri [String] Relative path from _links.next.href
    # @return [Hash] Parsed response
    def get_raw(uri)
      # Remove leading slash to ensure path is appended correctly
      path = uri.sub(%r{^/}, "")
      response = @conn.get(path) do |req|
        req.headers.merge!(bearer_headers(@user_token))
      end
      parse_response(response)
    end

    private

    def build_connection
      Faraday.new(url: @config.base_url) do |f|
        f.request :json
        f.response :json, content_type: /\bjson$/, parser_options: { symbolize_names: true }
        f.adapter Faraday.default_adapter
        f.options.timeout = @config.timeout
        f.options.open_timeout = @config.open_timeout
      end
    end

    def config_headers
      {
        "Authorization" => "Bearer #{@config.config_token}",
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      }
    end

    def bearer_headers(token)
      {
        "Authorization" => "Bearer #{token}",
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      }
    end

    def get(path, params = {}, auth_type: :bearer, raw: false)
      response = @conn.get(path, params) do |req|
        req.headers.merge!(auth_type == :config ? config_headers : bearer_headers(@user_token))
      end
      raw ? response.body : parse_response(response)
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
      raise ConnectionError.new("Connection failed: #{e.message}", original_error: e)
    end

    def post(path, body = {}, auth_type: :bearer, token: nil)
      response = @conn.post(path) do |req|
        case auth_type
        when :config
          req.headers.merge!(config_headers)
        when :none
          # No auth headers - used for /auth/renew with client creds in body
        else
          req.headers.merge!(bearer_headers(token || @user_token))
        end
        req.body = body
      end
      parse_response(response)
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
      raise ConnectionError.new("Connection failed: #{e.message}", original_error: e)
    end

    def put(path, body = {})
      response = @conn.put(path) do |req|
        req.headers.merge!(bearer_headers(@user_token))
        req.body = body
      end
      parse_response(response)
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
      raise ConnectionError.new("Connection failed: #{e.message}", original_error: e)
    end

    def delete(path)
      response = @conn.delete(path) do |req|
        req.headers.merge!(bearer_headers(@user_token))
      end
      return true if response.status == 204
      parse_response(response)
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
      raise ConnectionError.new("Connection failed: #{e.message}", original_error: e)
    end

    def parse_response(response)
      body = if response.body.is_a?(Hash)
               response.body
             elsif response.body.is_a?(String) && !response.body.empty?
               JSON.parse(response.body, symbolize_names: true) rescue {}
             else
               {}
             end

      case response.status
      when 200..201
        body
      when 204
        true
      when 401, 403
        error_code = body[:error] || body[:code]
        if error_code == "SCARequired"
          raise SCARequiredError.new(response.status, body)
        else
          raise AuthenticationError.new(response.status, body)
        end
      when 404
        raise NotFoundError.new(response.status, body)
      when 422
        raise ValidationError.new(response.status, body)
      when 429
        retry_after = response.headers["Retry-After"]&.to_i
        raise RateLimitError.new(response.status, body, retry_after: retry_after)
      else
        raise ApiError.new(response.status, body)
      end
    end
  end
end
