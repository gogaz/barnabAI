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
- 🔄 **Slack AI**: Uses the new Slack Agents interface for seamless Slack integration

## Prerequisites

- Ruby 4
- PostgreSQL
- A Slack workspace where you can install apps
- A GitHub account
- A Gemini API key (or another AI provider, feel free to implement yours!)

## Setup Guide

### 1. Clone and Install Dependencies

```bash
git clone <repository-url>
cd barnabaI
bundle install
```

### 2. Database Setup

Create and configure your PostgreSQL database:

```bash
# DATABASE_URL environment variable
# Format: postgresql://username:password@host:port/database_name
export DATABASE_URL=postgresql://postgres:your_password@localhost:5432/barnabai_development

# Run migrations
bin/rails db:create && rails db:migrate
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
3. In **Subscribe to bot events**, add:
   - `message.im` - Receive direct messages to the bot
   - `message.channels` - Receive messages in public channels (including threads)
   - `app_mention` - Receive mentions of the bot in channels


4. Click **Save Changes** at the bottom

5. **Reinstall the app to your workspace**:
   - Go back to **OAuth & Permissions**
   - Click **Reinstall to Workspace** (or **Install to Workspace** if not yet installed)
   - Authorize the app with the new event subscriptions

#### 3.5 Enable Agent mode

This enables the new Slack Agents interface, which allows the bot to be used in a sidebar and have AI-like direct messages.

### 4. GitHub OAuth App Setup

#### 4.1 Create a GitHub OAuth App

1. Go to your GitHub account → Settings → Developer settings → OAuth Apps
2. Click **New OAuth App**
3. Fill in:
   - **Application name**: BarnabAI
   - **Homepage URL**: your production URL
   - **Authorization callback URL**: `https://example.com/github/oauth/callback`
4. Click **Register application**
5. Copy the **Client ID** and generate a **Client Secret**


### 6. Environment Variables

Create a `.env` file in the root directory using .env.example as a template
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

**Starting Socket Mode**:

Run:
```bash
rails slack:connect
```

2. **Or start manually in Rails console**:
   ```bash
   bin/rails console
   # Then in the console:
   app_token = ENV.fetch("SLACK_APP_TOKEN")
   Slack::SocketConnector.start(app_token: app_token)
   ```

You should see connection logs indicating the WebSocket is connected.

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
3. **The bot understands**: Natural language commands like "What files changed on this specific PR?"

### Supported Intents

The bot can detect and execute many intents, take a look at actions for more information

### Token Encryption

All sensitive tokens (Slack bot tokens, GitHub tokens) are encrypted using `ActiveSupport::MessageEncryptor` before storage.
