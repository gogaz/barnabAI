# BarnabAI - Slack Chatbot for PR Management

BarnabAI is an intelligent Slack assistant that helps developers manage GitHub pull requests directly from Slack.
It uses AI to understand natural language commands and execute GitHub actions on your behalf.
It was heavily vibe-coded, use at your own risks.

<p align="center">
   <img height="256" alt="mascot_chill" src="https://github.com/user-attachments/assets/6332bdb3-d0db-4cbe-a84f-ba1104fdd785" />
</p>

## Features

- 🤖 **Intelligent Intent Detection**: Uses AI to understand what you want to do with PRs
- 👤 **Per-User GitHub Authentication**: Each user connects their own GitHub account
- 💬 **Conversational Interface**: Talk to the bot naturally in Slack
- 🎯 **PR Actions**: Merge, comment, approve, get info, create PRs, run specs, and more

## Prerequisites

- Ruby 4.0.1
- PostgreSQL
- A Slack workspace where you can install apps
- A GitHub account
- A Gemini API key (or another AI provider, feel free to implement yours!)

## Setup Guide

### 1. Clone and Install Dependencies

```bash
git clone <repository-url>
cd barnabAI
bundle install
```

### 2. Database Setup

Create and configure your PostgreSQL databases. The app uses separate databases for the main data, cache, queue, and Action Cable:

```bash
# Set in your .env file:
DATABASE_URL=postgresql://postgres:password@localhost:5432/barnabai_development
CACHE_DATABASE_URL=postgresql://postgres:password@localhost:5432/barnabai_development_cache
QUEUE_DATABASE_URL=postgresql://postgres:password@localhost:5432/barnabai_development_queue
CABLE_DATABASE_URL=postgresql://postgres:password@localhost:5432/barnabai_development_cable

# Run migrations
bin/rails db:create && bin/rails db:migrate
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
   - `channels:history` - Read channel history (for threads in public channels)
   - `channels:read` - View basic info about public channels (required for conversations.replies)
   - `chat:write` - Send messages
   - `im:history` - Read direct messages threads
   - `im:read` - Read direct messages
   - `im:write` - Send direct messages
   - `reactions:write` - Add reactions to messages
   - `users:read` - Read user information

3. Scroll up and click **Install to Workspace**
4. Copy the **Bot User OAuth Token** (starts with `xoxb-`) — this is your `SLACK_BOT_TOKEN`

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
3. In **Subscribe to bot events**, add:
   - `message.im` - Receive direct messages to the bot
   - `message.channels` - Receive messages in public channels (including threads)
   - `app_mention` - Receive mentions of the bot in channels


4. Click **Save Changes** at the bottom

5. **Reinstall the app to your workspace**:
   - Go back to **OAuth & Permissions**
   - Click **Reinstall to Workspace** (or **Install to Workspace** if not yet installed)
   - Authorize the app with the new event subscriptions

### 4. GitHub OAuth App Setup

#### 4.1 Create a GitHub OAuth App

1. Go to your GitHub account → Settings → Developer settings → OAuth Apps
2. Click **New OAuth App**
3. Fill in:
   - **Application name**: BarnabAI
   - **Homepage URL**: `APP_PROTOCOL://APP_HOST` (e.g. `https://example.com`)
   - **Authorization callback URL**: `APP_PROTOCOL://APP_HOST/github/oauth/callback` (e.g. `https://example.com/github/oauth/callback`)
4. Click **Register application**
5. Copy the **Client ID** and generate a **Client Secret**

### 5. Environment Variables

Create a `.env` file in the root directory using `.env.example` as a template:

```bash
cp .env.example .env
```

Then fill in the values:

| Variable | Description |
|---|---|
| `APP_HOST` | Your app's hostname (e.g. `example.com` or `localhost:3000`) |
| `APP_PROTOCOL` | `https` for production, `http` for local dev |
| `DATABASE_URL` | PostgreSQL connection string for the main database |
| `CACHE_DATABASE_URL` | PostgreSQL connection string for the cache database |
| `QUEUE_DATABASE_URL` | PostgreSQL connection string for the queue database |
| `CABLE_DATABASE_URL` | PostgreSQL connection string for the Action Cable database |
| `SLACK_APP_TOKEN` | App-level token from Socket Mode setup (starts with `xapp-`) |
| `SLACK_BOT_TOKEN` | Bot User OAuth Token from OAuth & Permissions (starts with `xoxb-`) |
| `SLACK_BOT_USER_ID` | Bot's Slack user ID — run `bin/rails slack:test_auth` to retrieve it |
| `GITHUB_CLIENT_ID` | GitHub OAuth App client ID |
| `GITHUB_CLIENT_SECRET` | GitHub OAuth App client secret |
| `LLM_PROVIDER` | LLM provider to use (currently only `gemini` is supported) |
| `GEMINI_API_KEY` | Your Gemini API key |
| `GEMINI_MODEL` | Gemini model to use (e.g. `gemini-2.5-flash`) |
| `ENABLE_SLACK_SOCKET_MODE` | Set to `true` to enable Socket Mode on startup |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | ActiveRecord encryption primary key |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | ActiveRecord encryption deterministic key |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | ActiveRecord encryption key derivation salt |

You can generate the ActiveRecord encryption keys with:

```bash
bin/rails db:encryption:init
```

### 6. Run the Application

```bash
# Start the Rails server
bin/rails server

# In another terminal, start the background job processor (for Solid Queue)
bin/rails solid_queue:start
```

The app will be available at `http://localhost:3000`

**Starting Socket Mode**:

If `ENABLE_SLACK_SOCKET_MODE` is set to `true`, Socket Mode starts automatically with the server. You can also start it manually:

```bash
bin/rails slack:connect
```

Or from the Rails console:
```bash
bin/rails console
# Then in the console:
app_token = ENV.fetch("SLACK_APP_TOKEN")
Slack::SocketConnector.start(app_token: app_token)
```

You should see connection logs indicating the WebSocket is connected.

### 7. Connect Your GitHub Account

Users need to connect their GitHub account to perform actions:

1. In Slack, mention the bot or send a message in a PR thread
2. The bot will prompt you to connect your GitHub account
3. Click the link to authorize GitHub access
4. You're all set!

**Note**: Each user must connect their own GitHub account. Actions are performed on behalf of the user who sent the message.

## Usage

### Basic Workflow

1. **Create a PR thread link**: When a PR is created, create a Slack thread and link it to the PR (this can be automated with webhooks)
2. **Talk to the bot**: Send messages in the PR thread
3. **The bot understands**: Natural language commands like "What files changed on this specific PR?"

### Supported Intents

The bot can detect and execute many intents, take a look at actions for more information

### Token Encryption

All sensitive tokens (Slack bot tokens, GitHub tokens) are encrypted using `ActiveRecord::Encryption` before storage. The three `ACTIVE_RECORD_ENCRYPTION_*` environment variables are required for this to work.
