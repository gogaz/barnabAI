# BarnabAI - Slack Chatbot for PR Management

BarnabAI is an intelligent Slack assistant that helps developers manage GitHub pull requests directly from Slack. It uses AI to understand natural language commands and execute GitHub actions on your behalf.

## Features

- 🤖 **Intelligent Intent Detection**: Uses AI to understand what you want to do with PRs
- 🔐 **Multi-Tenant Support**: Works across multiple Slack workspaces
- 👤 **Per-User GitHub Authentication**: Each user connects their own GitHub account
- 💬 **Conversational Interface**: Talk to the bot naturally in Slack threads
- 🎯 **PR Actions**: Merge, comment, approve, get info, create PRs, run specs, and more
- 🔄 **Context-Aware**: Remembers conversation history and PR context

## Prerequisites

- Ruby 3.2.3 or higher
- PostgreSQL 12 or higher
- A Slack workspace where you can install apps
- A GitHub account
- An OpenAI API key (or another AI provider)

## Architecture Overview

```
Slack Workspace (OAuth2) → SlackInstallation → Socket Mode Events
GitHub User (OAuth2) → User → GithubToken
Slack Message → ChatbotService → AIProvider → IntentDetection → ActionExecution
```

The app uses:
- **Slack OAuth2** for workspace installation (each workspace gets its own bot token)
- **GitHub OAuth2** for per-user authentication (each user connects their GitHub account)
- **Slack Socket Mode** for real-time event handling
- **AI Provider Abstraction** for easy swapping between AI models (OpenAI, Anthropic, etc.)

## Setup Guide

### 1. Clone and Install Dependencies

```bash
git clone <repository-url>
cd jessicAI
bundle install
```

### 2. Database Setup

Create and configure your PostgreSQL database:

```bash
# Create the database
createdb jessicai_development

# Or set environment variables for database connection
export DATABASE_USERNAME=postgres
export DATABASE_PASSWORD=your_password
export DATABASE_HOST=localhost
export DATABASE_PORT=5432

# Run migrations
bin/rails db:migrate
```

### 3. Slack App Setup

#### 3.1 Create a Slack App

1. Go to [https://api.slack.com/apps](https://api.slack.com/apps)
2. Click "Create New App" → "From scratch"
3. Name your app (e.g., "BarnabAI") and select your workspace
4. Click "Create App"

#### 3.2 Configure OAuth & Permissions

1. Go to **OAuth & Permissions** in the sidebar
2. Under **Scopes** → **Bot Token Scopes**, add:
   - `app_mentions:read` - Listen for app mentions
   - `chat:write` - Send messages
   - `channels:read` - Read channel information
   - `groups:read` - Read private channel information
   - `im:read` - Read direct messages
   - `im:write` - Send direct messages
   - `users:read` - Read user information

3. Under **Redirect URLs**, add:
   ```
   http://localhost:3000/slack/oauth/callback
   ```
   (Replace with your production URL when deploying)

4. Scroll up and click **Install to Workspace**
5. Copy the **Client ID** and **Client Secret**

#### 3.3 Enable Socket Mode

1. Go to **Socket Mode** in the sidebar
2. Toggle **Enable Socket Mode** to ON
3. Click **Generate** to create an App-Level Token
4. Name it (e.g., "Socket Mode Token")
5. Add scope: `connections:write`
6. Copy the **App-Level Token** (starts with `xapp-`)

**Note**: After enabling Socket Mode, make sure to complete step 3.4 (Subscribe to Events) before testing. Socket Mode won't receive events unless they're subscribed.

#### 3.4 Subscribe to Events (Required)

**Important**: Even when using Socket Mode, you must enable and subscribe to events in your Slack app configuration. Socket Mode only changes how events are delivered (via WebSocket instead of HTTP), but you still need to tell Slack which events to send.

1. Go to **Event Subscriptions** in the sidebar
2. Toggle **Enable Events** to ON
   - **Note**: You don't need to set a Request URL when using Socket Mode (leave it empty or ignore it)
3. Scroll down to **Subscribe to bot events** and add:
   - `message.im` - Receive direct messages to the bot
   - `app_mention` - Receive mentions of the bot in channels
   - `message.channels` - **Required** to receive messages in public channels (including thread replies)
   - `message.groups` - **Required** to receive messages in private channels (including thread replies)
   
   **Important**: Without `message.channels` and `message.groups`, you won't receive messages sent in threads, even if the bot is mentioned or the thread is related to a PR.

4. Click **Save Changes** at the bottom

5. **Reinstall the app to your workspace**:
   - Go back to **OAuth & Permissions**
   - Click **Reinstall to Workspace** (or **Install to Workspace** if not yet installed)
   - Authorize the app with the new event subscriptions

**Why this is needed**: Slack needs to know which events your app wants to receive. Socket Mode handles the delivery mechanism (WebSocket), but the event subscriptions tell Slack what to send.

### 4. GitHub OAuth App Setup

#### 4.1 Create a GitHub OAuth App

1. Go to your GitHub account → Settings → Developer settings → OAuth Apps
2. Click **New OAuth App**
3. Fill in:
   - **Application name**: BarnabAI
   - **Homepage URL**: `http://localhost:3000` (or your production URL)
   - **Authorization callback URL**: `http://localhost:3000/github/oauth/callback`
4. Click **Register application**
5. Copy the **Client ID** and generate a **Client Secret**

### 5. OpenAI API Setup

1. Go to [https://platform.openai.com/api-keys](https://platform.openai.com/api-keys)
2. Sign in or create an account
3. Click **Create new secret key**
4. Copy the API key (you won't see it again!)

**Note**: The app uses an AI provider abstraction layer, so you can easily swap OpenAI for other providers (Anthropic, Gemini, etc.) by implementing a new provider class.

### 6. Environment Variables

Create a `.env` file in the root directory (or set environment variables):

```bash
# Database
DATABASE_USERNAME=postgres
DATABASE_PASSWORD=your_password
DATABASE_HOST=localhost
DATABASE_PORT=5432

# Slack OAuth
SLACK_CLIENT_ID=your_slack_client_id
SLACK_CLIENT_SECRET=your_slack_client_secret
SLACK_APP_TOKEN=xapp-your-app-level-token

# GitHub OAuth
GITHUB_CLIENT_ID=your_github_client_id
GITHUB_CLIENT_SECRET=your_github_client_secret

# AI Provider
AI_PROVIDER=openai
OPENAI_API_KEY=sk-your-openai-api-key
OPENAI_MODEL=gpt-4

# Optional: Encryption keys (uses secret_key_base as fallback)
SLACK_TOKEN_ENCRYPTION_KEY=your-32-byte-key
GITHUB_TOKEN_ENCRYPTION_KEY=your-32-byte-key

# Optional: Enable Socket Mode on startup (for production)
ENABLE_SLACK_SOCKET_MODE=true
```

**For production**, use Rails credentials or a secrets management service:

```bash
# Edit credentials
EDITOR=vim bin/rails credentials:edit

# Add:
slack_token_encryption_key: your-encryption-key
github_token_encryption_key: your-encryption-key
```

### 7. Run the Application

```bash
# Start the Rails server
bin/rails server

# In another terminal, start the background job processor (for Solid Queue)
bin/rails solid_queue:start
```

The app will be available at `http://localhost:3000`

**Starting Socket Mode in Development**:

Socket Mode starts automatically in production, but in development you need to either:

1. **Set environment variable**:
   ```bash
   ENABLE_SLACK_SOCKET_MODE=true bin/rails server
   ```

2. **Or start manually in Rails console**:
   ```bash
   bin/rails console
   # Then in the console:
   SlackService.start_socket_mode
   ```

You should see connection logs indicating the WebSocket is connected. Check the logs for:
- `Slack Socket Mode WebSocket connection opened successfully`
- `Socket Mode hello received - connection ready`

### 8. Install the Slack App

1. Visit `http://localhost:3000` (or your production URL)
2. Click **Install to Slack**
3. Authorize the app in your workspace
4. You should see a success message

### 9. Connect Your GitHub Account

Users need to connect their GitHub account to perform actions:

1. In Slack, mention the bot or send a message in a PR thread
2. The bot will prompt you to connect your GitHub account
3. Click the link to authorize GitHub access
4. You'll be redirected back to Slack

**Note**: Each user must connect their own GitHub account. Actions are performed on behalf of the user who sent the message.

## Usage

### Basic Workflow

1. **Create a PR thread link**: When a PR is created, create a Slack thread and link it to the PR (this can be automated with webhooks)
2. **Talk to the bot**: Send messages in the PR thread
3. **The bot understands**: Natural language commands like:
   - "Merge this PR"
   - "Comment that I'll fix this later"
   - "What files changed?"
   - "Approve this PR"
   - "Run the specs"
   - "Show me PR #123"

### Supported Intents

The bot can detect and execute these intents:

- `merge_pr` - Merge a pull request
- `comment_on_pr` - Post a comment on GitHub
- `get_pr_info` - Get PR details and status
- `create_pr` - Create a new pull request
- `run_specs` - Trigger CI workflow
- `get_pr_files` - List changed files
- `approve_pr` - Approve a PR review
- `general_chat` - General conversation (no action)

### Example Commands

```
User: "Can you merge this PR?"
Bot: [Merges the PR] "Successfully merged PR #42"

User: "Tell Marc that I'll fix the typo"
Bot: [Posts comment on GitHub] "Comment posted on PR #42"

User: "What changed in this PR?"
Bot: [Shows file changes] "Files changed in PR #42: ..."

User: "Approve this"
Bot: [Approves PR] "Approved PR #42"
```

## Development

### Running Tests

```bash
bin/rails test
```

### Database Console

```bash
bin/rails dbconsole
```

### Rails Console

```bash
bin/rails console
```

### Background Jobs

The app uses Solid Queue for background jobs. Jobs are processed automatically when you run:

```bash
bin/rails solid_queue:start
```

Or in production, use a process manager like systemd or supervisor.

## Docker Deployment

BarnabAI is fully containerized and production-ready with Docker Compose. This is the recommended way to deploy the application.

### Prerequisites

- Docker 20.10+
- Docker Compose 2.0+

### Quick Start

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd jessicAI
   ```

2. **Set up environment variables**:
   ```bash
   # Copy the example environment file
   cp docker-compose.env.example .env.docker
   
   # Edit .env.docker and fill in all required values
   # You'll need:
   # - RAILS_MASTER_KEY (from config/master.key or generate with: bin/rails secret)
   # - SECRET_KEY_BASE (generate with: bin/rails secret)
   # - Database credentials (defaults are fine for development)
   # - Slack OAuth credentials (from https://api.slack.com/apps)
   # - GitHub OAuth credentials (from https://github.com/settings/developers)
   # - OpenAI API key (from https://platform.openai.com/api-keys)
   ```

3. **Build and start all services**:
   ```bash
   # Using docker-compose directly
   docker-compose --env-file .env.docker up -d
   
   # Or using the Makefile (recommended)
   make docker-setup  # Creates .env.docker if it doesn't exist
   make docker-build
   make docker-up
   ```

4. **Check service status**:
   ```bash
   docker-compose ps
   ```

5. **View logs**:
   ```bash
   # All services
   docker-compose logs -f
   
   # Specific service
   docker-compose logs -f web
   docker-compose logs -f jobs
   docker-compose logs -f slack_socket_mode
   ```

### Docker Compose Services

The `docker-compose.yml` includes the following services:

- **postgres**: PostgreSQL 16 database server
- **redis**: Redis 7 server (for Kredis)
- **web**: Rails web server (Puma/Thrust)
- **jobs**: Solid Queue background job worker
- **slack_socket_mode**: Dedicated service for Slack Socket Mode connection

### Environment Variables

All environment variables are configured in `.env.docker` (or passed via `--env-file`). See `docker-compose.env.example` for a complete list.

Key variables:
- `RAILS_ENV`: Set to `production` for production deployments
- `DATABASE_*`: PostgreSQL connection settings
- `SLACK_*`: Slack OAuth and Socket Mode credentials
- `GITHUB_*`: GitHub OAuth credentials
- `OPENAI_API_KEY`: Your OpenAI API key
- `RAILS_MASTER_KEY`: Rails master key for encrypted credentials

### Development with Docker

For local development with hot-reloading:

1. **Create override file**:
   ```bash
   cp docker-compose.override.yml.example docker-compose.override.yml
   ```

2. **Start services**:
   ```bash
   docker-compose --env-file .env.docker up
   ```

The override file mounts your local code directory, enabling live code changes without rebuilding.

### Common Commands

**Using Makefile (recommended)**:
```bash
make help              # Show all available commands
make docker-up         # Start all services
make docker-down       # Stop all services
make docker-logs       # View all logs
make docker-logs-web   # View web service logs
make docker-logs-jobs  # View jobs service logs
make docker-logs-slack # View Slack socket mode logs
make docker-migrate    # Run database migrations
make docker-console    # Open Rails console
make docker-shell      # Open shell in web container
make docker-restart    # Restart all services
make docker-clean      # Stop and remove volumes (⚠️ deletes data)
```

**Using docker-compose directly**:
```bash
# Start all services
docker-compose --env-file .env.docker up -d

# Stop all services
docker-compose down

# Stop and remove volumes (⚠️ deletes data)
docker-compose down -v

# Rebuild images
docker-compose --env-file .env.docker build

# Run database migrations
docker-compose --env-file .env.docker exec web bin/rails db:migrate

# Run Rails console
docker-compose --env-file .env.docker exec web bin/rails console

# View logs
docker-compose logs -f [service_name]

# Restart a specific service
docker-compose --env-file .env.docker restart web

# Scale job workers
docker-compose --env-file .env.docker up -d --scale jobs=3
```

### Production Considerations

1. **Security**:
   - Use strong passwords for database and secrets
   - Never commit `.env.docker` to version control
   - Use Docker secrets or a secrets management service in production
   - Regularly update base images

2. **Performance**:
   - Adjust `JOB_CONCURRENCY` based on your workload
   - Scale job workers as needed: `docker-compose up -d --scale jobs=N`
   - Configure `RAILS_MAX_THREADS` based on your server capacity

3. **Monitoring**:
   - Set up log aggregation (e.g., ELK stack, Datadog)
   - Monitor service health with healthchecks
   - Set up alerts for service failures

4. **Backups**:
   - Regularly backup PostgreSQL volumes
   - Use `docker-compose exec postgres pg_dump` for database backups
   - Consider using managed database services for production

### Troubleshooting Docker

**Services won't start**:
- Check logs: `docker-compose logs [service_name]`
- Verify environment variables are set correctly
- Ensure ports aren't already in use

**Database connection errors**:
- Wait for PostgreSQL to be healthy: `docker-compose ps`
- Check database credentials in `.env.docker`
- Verify network connectivity: `docker-compose exec web ping postgres`

**Slack Socket Mode not connecting**:
- Check `slack_socket_mode` service logs: `docker-compose logs -f slack_socket_mode`
- Verify `SLACK_APP_TOKEN` is correct (starts with `xapp-`)
- Ensure Socket Mode is enabled in Slack app settings
- Verify event subscriptions are configured (see section 3.4)
- Check that the app is reinstalled after adding event subscriptions

## Production Deployment

### Environment Variables

Set all required environment variables in your production environment:

```bash
# Required
SLACK_CLIENT_ID=...
SLACK_CLIENT_SECRET=...
SLACK_APP_TOKEN=...
GITHUB_CLIENT_ID=...
GITHUB_CLIENT_SECRET=...
OPENAI_API_KEY=...
DATABASE_URL=postgresql://...

# Optional
AI_PROVIDER=openai
OPENAI_MODEL=gpt-4
ENABLE_SLACK_SOCKET_MODE=true
```

### Database

Ensure PostgreSQL is running and accessible. Run migrations:

```bash
RAILS_ENV=production bin/rails db:migrate
```

### Background Jobs

Start the Solid Queue worker:

```bash
RAILS_ENV=production bin/rails solid_queue:start
```

Or use a process manager to keep it running.

### Socket Mode

Socket Mode connection starts automatically if `ENABLE_SLACK_SOCKET_MODE=true`. The connection is maintained by the `MaintainSlackConnectionsJob` which should run periodically.

## Architecture Details

### Multi-Tenant Support

- Each `SlackInstallation` represents one workspace installation
- Each `User` belongs to a workspace and can have multiple `GithubToken`s
- All data is scoped by `slack_installation_id` for isolation

### AI Provider Abstraction

The app uses an abstraction layer for AI providers:

- `BaseProvider` - Abstract interface
- `OpenAIProvider` - OpenAI implementation
- `AIProviderFactory` - Factory for creating providers

To add a new provider, implement `BaseProvider` and update the factory.

### Intent Detection

Intent detection uses the AI provider's structured output capabilities:

- **OpenAI**: Function calling (tools API)
- **Other providers**: JSON mode with schema

Intents are defined in `IntentDetectionService::INTENT_SCHEMA`.

### Token Encryption

All sensitive tokens (Slack bot tokens, GitHub tokens) are encrypted using `ActiveSupport::MessageEncryptor` before storage.

## Troubleshooting

### Socket Mode Not Connecting

- Verify `SLACK_APP_TOKEN` is set correctly (starts with `xapp-`)
- Check that Socket Mode is enabled in Slack app settings
- Check Rails logs for connection errors

### Events Not Being Received

If the WebSocket connection is established but you're not receiving events (e.g., direct messages):

1. **Verify event subscriptions**:
   - Go to **Event Subscriptions** in your Slack app settings
   - Ensure **Enable Events** is toggled ON
   - Verify `message.im` and `app_mention` are listed under **Subscribe to bot events**

2. **Reinstall the app**:
   - After adding event subscriptions, you must reinstall the app to your workspace
   - Go to **OAuth & Permissions** → **Reinstall to Workspace**

3. **Check Rails logs**:
   - Look for `📨 Received Slack Event` messages
   - If you see connection logs but no events, the subscriptions are likely missing

4. **Verify bot installation**:
   - Ensure the bot is installed in your workspace
   - Check that `SlackInstallation` exists in your database with the correct `team_id`

### GitHub Actions Failing

- Ensure user has connected their GitHub account
- Verify GitHub token is valid (not expired)
- Check user has necessary permissions on the repository

### Intent Detection Not Working

- Verify `OPENAI_API_KEY` is set and valid
- Check API rate limits
- Review logs for AI provider errors

### Database Connection Issues

- Verify PostgreSQL is running
- Check database credentials
- Ensure database exists: `createdb jessicai_development`

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

[Your License Here]

## Support

For issues and questions, please open an issue on GitHub.
