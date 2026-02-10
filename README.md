# Powens Ruby

A Ruby client for the [Powens Open Banking API](https://docs.powens.com/) (formerly Budget Insight). Connect bank accounts, retrieve transactions, and manage financial data through Powens' aggregation platform.

## Features

- Full API coverage: users, connectors, connections, accounts, transactions, investments
- Automatic pagination for large datasets
- Webview URL generation for bank connection flows
- Strong Customer Authentication (SCA) support
- Comprehensive error handling with specific error classes
- Configurable timeouts and retry settings

## Installation

Add to your Gemfile:

```ruby
gem 'powens', github: 'bdiallo/powens-ruby'
```

Then run:

```bash
bundle install
```

## Configuration

Configure the client with your Powens credentials:

```ruby
Powens.configure do |config|
  config.domain = "your-domain"           # Your Powens domain (e.g., "company-sandbox")
  config.config_token = "xxx"             # Config token from Powens Console
  config.client_id = "xxx"                # Client ID from Powens Console
  config.client_secret = "xxx"            # Client secret from Powens Console
  config.environment = :sandbox           # :sandbox or :production
  config.timeout = 30                     # Request timeout in seconds
  config.open_timeout = 10                # Connection timeout in seconds
end
```

### Rails Configuration

Create an initializer at `config/initializers/powens.rb`:

```ruby
Powens.configure do |config|
  config.domain = Rails.application.credentials.dig(:powens, :domain) ||
                  ENV.fetch('POWENS_DOMAIN', 'company-sandbox')
  config.config_token = Rails.application.credentials.dig(:powens, :config_token) ||
                        ENV.fetch('POWENS_CONFIG_TOKEN', '')
  config.client_id = Rails.application.credentials.dig(:powens, :client_id) ||
                     ENV.fetch('POWENS_CLIENT_ID', '')
  config.client_secret = Rails.application.credentials.dig(:powens, :client_secret) ||
                         ENV.fetch('POWENS_CLIENT_SECRET', '')
  config.environment = Rails.env.production? ? :production : :sandbox
end
```

## Usage

### Basic Usage

```ruby
# Create a client with config token (for public endpoints)
client = Powens.client

# List available bank connectors
connectors = client.list_connectors
connectors[:connectors].each do |connector|
  puts "#{connector[:id]}: #{connector[:name]}"
end
```

### Authentication Flow

Powens uses a multi-step authentication process:

```ruby
# Step 1: Create a temporary user
client = Powens.client
temp_result = client.create_user
# => { auth_token: "temp_xxx", type: "temporary", id_user: 42 }

# Step 2: Exchange for permanent token
perm_result = client.get_permanent_token(temp_result[:auth_token])
# => { token: "perm_yyy", type: "permanent" }

# Step 3: Create client with user token
user_client = Powens.client(user_token: perm_result[:token])

# Step 4: Generate temporary code for webview
code_result = user_client.create_temporary_code
# => { code: "abc123", type: "temporary", expires_in: 3600 }

# Step 5: Build webview URL for bank connection
webview_url = user_client.webview_url
# => "https://webview.powens.com/connect?token=perm_yyy"
```

### Managing Connections

```ruby
client = Powens.client(user_token: "user_token")

# List user's bank connections
connections = client.list_connections
connections[:connections].each do |conn|
  puts "Connection #{conn[:id]}: #{conn[:state]} - Error: #{conn[:error]}"
end

# Get specific connection
connection = client.get_connection(100)

# Trigger a sync
client.sync_connection(100)

# Delete a connection
client.delete_connection(100)

# Generate reconnect URL for SCA
reconnect_url = client.webview_reconnect_url(100)
```

### Working with Accounts

```ruby
client = Powens.client(user_token: "user_token")

# List all accounts
accounts = client.list_accounts
accounts[:accounts].each do |account|
  puts "#{account[:name]}: #{account[:balance]} #{account[:currency]}"
end

# Get specific account
account = client.get_account(1000)

# List accounts for a specific connection
accounts = client.list_accounts(connection_id: 100)

# Update account settings
client.update_account(1000, disabled: true)
```

### Fetching Transactions

```ruby
client = Powens.client(user_token: "user_token")

# List transactions with filters
transactions = client.list_transactions(
  min_date: "2024-01-01",
  max_date: "2024-12-31",
  limit: 100
)

# Fetch all transactions with automatic pagination
all_transactions = client.all_transactions(min_date: 30.days.ago)

# Stream processing (memory efficient for large datasets)
client.all_transactions(min_date: 30.days.ago) do |tx|
  Transaction.create!(
    external_id: tx[:id],
    description: tx[:wording],
    amount: tx[:value],
    date: tx[:date]
  )
end

# Get transactions for a specific account
transactions = client.list_transactions(account_id: 1000)
```

### Investments & Wealth

```ruby
client = Powens.client(user_token: "user_token")

# List investment positions
investments = client.list_investments
investments[:investments].each do |inv|
  puts "#{inv[:label]}: #{inv[:quantity]} x #{inv[:unitvalue]}"
end

# Get balance history
balances = client.get_balances(min_date: "2024-01-01", max_date: "2024-01-31")
```

### Categories

```ruby
client = Powens.client

# List transaction categories
categories = client.list_categories
categories[:categories].each do |cat|
  puts "#{cat[:id]}: #{cat[:name]}"
end
```

## Error Handling

The gem provides specific error classes for different scenarios:

```ruby
begin
  client.list_accounts
rescue Powens::AuthenticationError => e
  # 401/403 - Invalid or expired token
  puts "Auth error: #{e.message}"

rescue Powens::SCARequiredError => e
  # 403 with SCARequired - Strong Customer Authentication needed
  puts "SCA required - redirect user to webview"
  redirect_to client.webview_reconnect_url(connection_id)

rescue Powens::NotFoundError => e
  # 404 - Resource not found
  puts "Not found: #{e.message}"

rescue Powens::ValidationError => e
  # 422 - Invalid parameters
  puts "Validation error: #{e.body}"

rescue Powens::RateLimitError => e
  # 429 - Rate limit exceeded
  puts "Rate limited - retry after #{e.retry_after} seconds"
  sleep(e.retry_after)
  retry

rescue Powens::ConnectionError => e
  # Network/timeout errors
  puts "Connection failed: #{e.message}"
  puts "Original error: #{e.original_error}"

rescue Powens::ConfigurationError => e
  # Missing configuration
  puts "Configuration error: #{e.message}"

rescue Powens::ApiError => e
  # Generic API error
  puts "API error #{e.status}: #{e.error_code}"
end
```

## Webhook Handling

Powens sends webhooks for connection state changes. Example webhook handler:

```ruby
# In your webhook controller/endpoint
class WebhooksController < ApplicationController
  skip_before_action :authenticate_user!

  def powens
    verify_webhook_signature!

    event_type = request.headers['X-Powens-Event'] || params[:push_type]

    case event_type
    when 'CONNECTION_SYNCED', 'connection'
      handle_connection_synced(params)
    when 'CONNECTION_DELETED'
      handle_connection_deleted(params)
    end

    head :ok
  end

  private

  def verify_webhook_signature!
    secret = ENV['POWENS_WEBHOOK_SECRET']
    return if secret.blank?

    provided = request.headers['Authorization']&.delete_prefix('Bearer ')
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(provided.to_s, secret)
  end

  def handle_connection_synced(payload)
    connection = BankConnection.find_by(external_user_id: payload[:user][:id])
    return unless connection

    error = payload.dig(:connection, :error)
    status = error.nil? ? 'connected' : map_error_to_status(error)

    connection.update!(
      external_connection_id: payload[:connection][:id],
      status: status,
      error_message: payload[:connection][:error_message]
    )

    # Trigger sync job if connected
    SyncBankDataJob.perform_later(connection.id) if status == 'connected'
  end

  def map_error_to_status(error)
    case error
    when 'SCARequired' then 'sca_needed'
    when 'webauthRequired' then 'webauth_needed'
    when 'wrongpass' then 'credentials_error'
    else 'error'
    end
  end
end
```

## API Reference

### Client Methods

#### Authentication
- `create_user` - Create temporary user
- `get_permanent_token(temp_token)` - Exchange for permanent token
- `create_temporary_code` - Generate code for webview
- `get_user(user_id = "me")` - Get user info
- `delete_user(user_id)` - Delete user

#### Webview URLs
- `webview_url(token: nil, connector_ids: nil)` - Bank connection URL
- `webview_reconnect_url(connection_id, token: nil)` - Reconnection URL

#### Connectors
- `list_connectors(expand: nil)` - List available banks
- `get_connector(connector_id)` - Get connector details

#### Connections
- `list_connections(user_id: "me")` - List user connections
- `get_connection(connection_id, user_id: "me")` - Get connection
- `sync_connection(connection_id, user_id: "me")` - Trigger sync
- `delete_connection(connection_id, user_id: "me")` - Delete connection

#### Accounts
- `list_accounts(user_id: "me", connection_id: nil)` - List accounts
- `get_account(account_id, user_id: "me")` - Get account
- `update_account(account_id, user_id: "me", **attrs)` - Update account

#### Transactions
- `list_transactions(...)` - List with filters
- `all_transactions(..., &block)` - Fetch all with pagination
- `get_transaction(transaction_id, user_id: "me")` - Get transaction
- `update_transaction(transaction_id, user_id: "me", **attrs)` - Update

#### Investments
- `list_investments(user_id: "me", account_id: nil)` - List positions
- `list_market_orders(user_id: "me")` - List orders

#### Other
- `get_balances(user_id: "me", min_date: nil, max_date: nil)` - Balance history
- `list_categories` - Transaction categories
- `get_category(category_id)` - Category details
- `list_account_types` - Account type definitions
- `list_documents(user_id: "me")` - User documents

## Integration Workflows

These diagrams show how to integrate this gem into your application.

### First Bank Connection

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   YOUR APP      │     │  YOUR BACKEND   │     │   POWENS API    │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         │  1. User taps         │                       │
         │     "Connect Bank"    │                       │
         │──────────────────────>│                       │
         │                       │                       │
         │                       │  2. POST /auth/init   │
         │                       │──────────────────────>│
         │                       │<──────────────────────│
         │                       │  {auth_token, id_user}│
         │                       │                       │
         │                       │  3. POST /auth/token/ │
         │                       │     access            │
         │                       │──────────────────────>│
         │                       │<──────────────────────│
         │                       │  {permanent_token}    │
         │                       │                       │
         │                       │  4. POST /auth/token/ │
         │                       │     code              │
         │                       │──────────────────────>│
         │                       │<──────────────────────│
         │                       │  {temp_code}          │
         │                       │                       │
         │<──────────────────────│                       │
         │  {webview_url}        │                       │
         │                       │                       │
         │  5. Open webview      │                       │
         │     (InAppBrowser)    │                       │
         │──────────────────────────────────────────────>│
         │                       │                       │
         │  6. User selects      │                       │
         │     bank and enters   │                       │
         │     credentials       │                       │
         │                       │                       │
         │<──────────────────────────────────────────────│
         │  7. Redirect to       │                       │
         │     your callback     │                       │
         │     ?connection_id=X  │                       │
         │                       │                       │
         │  8. POST /callback    │                       │
         │──────────────────────>│                       │
         │                       │                       │
         │                       │<──────────────────────│
         │                       │  9. WEBHOOK:          │
         │                       │     CONNECTION_SYNCED │
         │                       │                       │
         │                       │  10. Sync accounts    │
         │                       │      & transactions   │
         │                       │                       │
         │<──────────────────────│                       │
         │  {success: true}      │                       │
         │                       │                       │
         │  11. Show success     │                       │
         │      "Bank connected!"│                       │
         └───────────────────────┴───────────────────────┘
```

### SCA Re-authentication (PSD2)

Banks require periodic re-authentication (~90 days) per PSD2 regulations.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         SCA TRIGGERS                                │
├─────────────────────────────────────────────────────────────────────┤
│  - Bank requires validation every ~90 days (PSD2/DSP2)              │
│  - User changed password at bank                                    │
│  - Bank requires new security verification                          │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   POWENS API    │     │  YOUR BACKEND   │     │   YOUR APP      │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         │  1. WEBHOOK:          │                       │
         │     CONNECTION_SYNCED │                       │
         │     error: SCARequired│                       │
         │──────────────────────>│                       │
         │                       │                       │
         │                       │  2. Update connection │
         │                       │     status: sca_needed│
         │                       │                       │
         │                       │  3. Push notification │
         │                       │──────────────────────>│
         │                       │  "Bank verification   │
         │                       │   required"           │
         │                       │                       │
         │                       │                       │  4. User opens
         │                       │                       │     your app
         │                       │                       │
         │                       │<──────────────────────│
         │                       │  GET /connections     │
         │                       │                       │
         │                       │──────────────────────>│
         │                       │  [{status: sca_needed,│
         │                       │    error_message:...}]│
         │                       │                       │
         │                       │       ┌───────────────────────┐
         │                       │       │  ALERT BANNER         │
         │                       │       │  "Your bank requires  │
         │                       │       │   verification"       │
         │                       │       │  [Reconnect]          │
         │                       │       └───────────────────────┘
         │                       │                       │
         │                       │<──────────────────────│
         │                       │  5. POST /reconnect   │
         │                       │                       │
         │  6. Generate new code │                       │
         │<──────────────────────│                       │
         │                       │                       │
         │──────────────────────>│                       │
         │  {reconnect_url}      │──────────────────────>│
         │                       │                       │
         │                       │                       │  7. Open
         │                       │                       │     webview
         │<──────────────────────────────────────────────│
         │                       │                       │
         │  8. User validates    │                       │
         │     with bank app     │                       │
         │                       │                       │
         │  9. WEBHOOK:          │                       │
         │     CONNECTION_SYNCED │                       │
         │     error: null       │                       │
         │──────────────────────>│                       │
         │                       │                       │
         │                       │  10. Update status:   │
         │                       │      connected        │
         │                       │                       │
         │                       │  11. Trigger sync     │
         │                       │                       │
         │                       │──────────────────────>│
         │                       │  "Bank reactivated!"  │
         └───────────────────────┴───────────────────────┘
```

### Disconnect Bank Account

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   YOUR APP      │     │  YOUR BACKEND   │     │   POWENS API    │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         │  1. User taps         │                       │
         │     "Disconnect"      │                       │
         │                       │                       │
         │       ┌───────────────────────────────┐       │
         │       │   CONFIRMATION DIALOG         │       │
         │       │   "Are you sure you want to   │       │
         │       │    disconnect this account?"  │       │
         │       │   [Cancel]  [Disconnect]      │       │
         │       └───────────────────────────────┘       │
         │                       │                       │
         │  2. DELETE            │                       │
         │     /connections/:id  │                       │
         │──────────────────────>│                       │
         │                       │                       │
         │                       │  3. DELETE /users/me/ │
         │                       │     connections/:id   │
         │                       │──────────────────────>│
         │                       │<──────────────────────│
         │                       │  204 No Content       │
         │                       │                       │
         │                       │  4. Update connection │
         │                       │     status:           │
         │                       │     disconnected      │
         │                       │                       │
         │                       │  5. Keep or archive   │
         │                       │     historical data   │
         │                       │                       │
         │<──────────────────────│                       │
         │  {success: true}      │                       │
         │                       │                       │
         │  6. Remove from       │                       │
         │     connections list  │                       │
         └───────────────────────┴───────────────────────┘
```

### Scheduled Daily Sync

```
┌─────────────────────────────────────────────────────────────────────┐
│                    BACKGROUND JOB: DailySyncJob                     │
│                    Runs every day (e.g., 6:00 AM)                   │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  YOUR BACKEND   │     │   POWENS API    │     │   YOUR APP      │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         │  1. Query connections │                       │
         │     WHERE status =    │                       │
         │     'connected' AND   │                       │
         │     last_sync > 24h   │                       │
         │                       │                       │
         ├───────────────────────┤                       │
         │  For each connection: │                       │
         ├───────────────────────┤                       │
         │                       │                       │
         │  2. GET /users/me/    │                       │
         │     accounts          │                       │
         │──────────────────────>│                       │
         │<──────────────────────│                       │
         │  [{id, balance,...}]  │                       │
         │                       │                       │
         │  3. GET /users/me/    │                       │
         │     transactions      │                       │
         │     ?min_date=        │                       │
         │     last_sync_date    │                       │
         │──────────────────────>│                       │
         │<──────────────────────│                       │
         │  [{id, amount,...}]   │                       │
         │                       │                       │
         │  4. Upsert accounts   │                       │
         │     Update balances   │                       │
         │                       │                       │
         │  5. Deduplicate &     │                       │
         │     insert new        │                       │
         │     transactions      │                       │
         │                       │                       │
         │  6. Update connection │                       │
         │     last_synced_at    │                       │
         │                       │                       │
         │  7. If significant    │                       │
         │     new transactions  │──────────────────────>│
         │                       │  Push notification:   │
         │                       │  "5 new transactions" │
         │                       │                       │
         └───────────────────────┴───────────────────────┘
```

## Connection State Machine

```
                    ┌─────────────┐
                    │   PENDING   │
                    │  (created)  │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼
       ┌──────────┐  ┌──────────┐  ┌──────────┐
       │  ERROR   │  │CONNECTED │  │  FAILED  │
       │(webview  │  │ (active) │  │(user     │
       │ failed)  │  │          │  │ abandoned│
       └──────────┘  └────┬─────┘  └──────────┘
                          │
           ┌──────────────┼──────────────┐
           │              │              │
           ▼              ▼              ▼
    ┌────────────┐  ┌──────────┐  ┌────────────┐
    │ SCA_NEEDED │  │ SYNCING  │  │DISCONNECTED│
    │ (requires  │  │(refresh  │  │ (revoked   │
    │  reauth)   │  │ in prog) │  │  by user)  │
    └─────┬──────┘  └────┬─────┘  └────────────┘
          │              │
          │   ┌──────────┘
          │   │
          ▼   ▼
    ┌──────────────┐
    │  CONNECTED   │
    │  (restored)  │
    └──────────────┘
```

## Powens Error Codes

| Error Code | Description | Recommended Action |
|------------|-------------|-------------------|
| `SCARequired` | Strong Customer Authentication needed | Show reconnect webview |
| `webauthRequired` | Web authentication required | Show reconnect webview |
| `wrongpass` | Invalid bank credentials | Prompt user to reconnect with correct credentials |
| `websiteUnavailable` | Bank website temporarily unavailable | Retry sync later |
| `additionalInformationNeeded` | Bank requires additional info | Show webview for user input |
| `actionNeeded` | User action required at bank | Show webview |
| `decoupled` | Decoupled authentication in progress | Wait and poll for completion |
| `bug` | Internal Powens error | Contact Powens support |

## Development

```bash
git clone https://github.com/bdiallo/powens-ruby.git
cd powens-ruby
bundle install
bundle exec rspec
```

## License

MIT License - see [LICENSE](LICENSE) file.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Add tests for your changes
4. Commit your changes (`git commit -am 'Add new feature'`)
5. Push to the branch (`git push origin feature/my-feature`)
6. Create a Pull Request
