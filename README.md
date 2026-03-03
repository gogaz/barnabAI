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
- 🔔 **Extensible Notification System**: AI-powered notifications with per-user settings via the Slack App Home Tab. Ships with CI failure analysis and PR review digest. Fork-friendly — add custom notification types by dropping a class in `app/services/notifications/types/`.

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

The repo includes a ready-made app manifest at [`slack_app_manifest.json`](slack_app_manifest.json) that configures all scopes, events, Socket Mode, Home Tab, and interactivity in one shot.

#### 3.1 Create the Slack App from Manifest

1. Go to [https://api.slack.com/apps?new_app=1](https://api.slack.com/apps?new_app=1)
2. Choose **"From an app manifest"**
3. Select your workspace
4. Paste the contents of `slack_app_manifest.json` (switch to JSON mode if needed)
5. Before confirming, replace `YOUR_HOST` in the `redirect_urls` with your actual hostname
6. Click **Create**

#### 3.2 Collect Tokens

1. Go to **OAuth & Permissions** → click **Install to Workspace** → copy the **Bot User OAuth Token** (starts with `xoxb-`) — this is your `SLACK_BOT_TOKEN`
2. Go to **Basic Information** → under **App-Level Tokens**, click **Generate Token and Scopes** → name it (e.g., "Socket Mode Token") → add scope `connections:write` → copy the token (starts with `xapp-`) — this is your `SLACK_APP_TOKEN`

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

### 5. GitHub Webhook Setup

The notification system and PR tracking rely on receiving GitHub webhook events. You need to configure a webhook on each repository (or organization) you want the bot to monitor.

1. Go to your GitHub repository → **Settings** → **Webhooks** → **Add webhook**
   - For organization-wide coverage, go to your **Organization Settings** → **Webhooks** instead
2. Fill in:
   - **Payload URL**: `APP_PROTOCOL://APP_HOST/github/webhooks` (e.g. `https://example.com/github/webhooks`)
   - **Content type**: `application/json`
   - **Secret**: *(optional but recommended — not yet enforced by the app)*
3. Under **Which events would you like to trigger this webhook?**, select **Send me everything**
   - The app processes `pull_request` events (for PR tracking and assignee updates) and forwards all events to the notification dispatcher. Sending all events ensures current and future notification types work correctly.
4. Make sure **Active** is checked, then click **Add webhook**

> **Why "Send me everything"?** The notification framework is extensible — built-in types listen to `check_suite` and `pull_request_review` events, and custom notification types added via forks may listen to any event. Sending all events avoids having to reconfigure the webhook each time a new notification type is added.

### 6. Environment Variables

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
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | ActiveRecord encryption primary key |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | ActiveRecord encryption deterministic key |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | ActiveRecord encryption key derivation salt |

You can generate the ActiveRecord encryption keys with:

```bash
bin/rails db:encryption:init
```

### 7. Run the Application

```bash
# Start the Rails server
bin/rails server

# In another terminal, start the background job processor (for Solid Queue)
bin/rails solid_queue:start
```

The app will be available at `http://localhost:3000`

**Starting Socket Mode**:

You can start it either ways:

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

### 8. Connect Your GitHub Account

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
