# Claude Code Gateway

[繁體中文版 README](README_zh-TW.md)

> **Disclaimer:** This project does **not** extract or use OAuth tokens. It runs the official Claude Code CLI binary inside a Docker container as a subprocess. This may still fall outside Anthropic's intended usage of Claude Code subscriptions. Review [Anthropic's Consumer Terms of Service](https://www.anthropic.com/legal/consumer-terms) before using. **Use at your own risk.**

> Turn your Claude Code subscription into a secured API endpoint for any AI agent -- no separate Anthropic API key needed.

## What Is Claude Code Gateway?

Claude Code Gateway is a Python FastAPI server that wraps the Claude Code CLI as an OpenAI-compatible API. It exposes `/v1/chat/completions` so any OpenAI-compatible tool can use Claude models through your existing subscription. No per-token billing.

This fork adds an **nginx reverse proxy** with API key authentication and security hardening.

## Architecture

```
Client (Cline / Aider / Langfuse / ...)
  │  Authorization: Bearer <GATEWAY_API_KEY>
  ▼
nginx (127.0.0.1:8080 HTTP / :8443 HTTPS)
  │  ├─ /health → bypass auth
  │  ├─ CORS headers for browser extensions
  │  └─ /* → verify Bearer token
  ▼
FastAPI (api:8080, internal only)
  │  ├─ POST /v1/chat/completions → Claude CLI subprocess
  │  ├─ GET  /v1/models → model list
  │  └─ GET  /health → health check
  ▼
Claude Code CLI (Node.js)
  └─ authenticates via ~/.claude/.credentials.json
```

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/yves8833/claude-code-gateway.git
cd claude-code-gateway
cp .env.example .env
```

### 2. Set API key

Edit `.env` and add your gateway API key:

```bash
# Generate a random key
echo "GATEWAY_API_KEY=ccg-$(openssl rand -hex 16)" >> .env
```

Or set your own:

```
GATEWAY_API_KEY=your-secret-key-here
```

### 3. Sync Claude CLI credentials

Newer versions of Claude CLI store credentials in macOS Keychain instead of a file. The included sync script exports them for Docker:

```bash
# First time: run claude and complete the login flow if you haven't already
claude

# Sync credentials from Keychain to file
./scripts/sync-credentials.sh
```

To enable automatic syncing (every hour + on login):

```bash
# Install the LaunchAgent
cp scripts/com.claude-gateway.sync-credentials.plist ~/Library/LaunchAgents/
# Edit the plist to update paths if your project directory differs
launchctl load ~/Library/LaunchAgents/com.claude-gateway.sync-credentials.plist
```

Manage the LaunchAgent:

```bash
# Check status
launchctl list | grep claude-gateway

# Manual trigger
./scripts/sync-credentials.sh

# View logs
cat logs/sync-credentials.log

# Disable
launchctl unload ~/Library/LaunchAgents/com.claude-gateway.sync-credentials.plist
```

### 4. Generate HTTPS certificates (optional but recommended)

```bash
# Install mkcert (macOS)
brew install mkcert
mkcert -install

# Generate trusted local certs
mkdir -p certs
mkcert -cert-file certs/localhost.pem -key-file certs/localhost-key.pem localhost 127.0.0.1
```

### 5. Start

```bash
docker compose up --build -d
```

Verify:

```bash
# Health check (no auth required)
curl http://localhost:8080/health

# Test HTTP
curl http://localhost:8080/v1/models \
  -H "Authorization: Bearer YOUR_API_KEY"

# Test HTTPS
curl https://localhost:8443/v1/models \
  -H "Authorization: Bearer YOUR_API_KEY"
```

## Security

This fork adds several security layers over the original project:

| Layer | Detail |
|-------|--------|
| **nginx reverse proxy** | API service not directly exposed |
| **HTTPS (TLS)** | Port 8443 with mkcert trusted certificates |
| **API key authentication** | All requests require `Authorization: Bearer <key>` |
| **CORS** | Browser extensions (e.g. Immersive Translate) can connect |
| **localhost binding** | `127.0.0.1:8080/:8443` -- not accessible from network |
| **Minimal credential mount** | Only `.credentials.json`, not the entire `~/.claude` directory |
| **Credential auto-sync** | LaunchAgent syncs Keychain → file every hour, restarts container on change |
| **Health endpoint bypass** | `/health` accessible without auth for monitoring |

### Why minimal mount matters

Mounting the full `~/.claude` directory causes the CLI to hang due to task lock files, plugin configs, and MCP server definitions. Mounting only `.credentials.json` fixes this and reduces the attack surface.

## Available Models

Any `claude-*` model name is passed through directly to the CLI. GPT model names are mapped automatically.

| Model | ID |
|-------|----|
| Claude Sonnet 4 | `claude-sonnet-4-20250514` |
| Claude Sonnet 4.6 | `claude-sonnet-4-6` |
| Claude Opus 4 | `claude-opus-4-20250514` |
| Claude Opus 4.6 | `claude-opus-4-6` |
| Claude Haiku 4.5 | `claude-haiku-4-5-20251001` |

Shorthand aliases: `sonnet`, `opus`, `haiku`
GPT aliases: `gpt-4o` → Sonnet 4, `gpt-3.5-turbo` → Haiku 4.5

## Platform Integration

For any platform, use these settings:

| Setting | Value |
|---------|-------|
| **Base URL (HTTP)** | `http://localhost:8080/v1` |
| **Base URL (HTTPS)** | `https://localhost:8443/v1` |
| **API Key** | Your `GATEWAY_API_KEY` value |
| **Adapter / Provider** | OpenAI |

> If connecting from another Docker container, use `http://host.docker.internal:8080/v1` as the base URL.
> Browser extensions require HTTPS: use `https://localhost:8443/v1`.

### Immersive Translate (Browser Extension)

In Immersive Translate settings, choose **OpenAI Custom** service:

- API URL: `https://localhost:8443/v1/chat/completions`
- API Key: your `GATEWAY_API_KEY`
- Model: `claude-haiku-4-5-20251001` (recommended for translation)

> Browser extensions must use HTTPS (port 8443). HTTP will fail due to security restrictions.

### Langfuse

In Langfuse Settings → LLM Connections:

- Provider name: `claude-gateway`
- Adapter: `openai`
- Base URL: `http://host.docker.internal:8080/v1`
- API Key: your `GATEWAY_API_KEY`
- Custom models: `claude-sonnet-4-20250514`, `claude-opus-4-6`, etc.

### Cline

In Cline settings, set API Provider to "OpenAI Compatible":

- Base URL: `http://localhost:8080/v1`
- API Key: your `GATEWAY_API_KEY`
- Model: `claude-sonnet-4-20250514`

### Aider

```bash
aider --openai-api-base http://localhost:8080/v1 \
      --openai-api-key YOUR_API_KEY
```

### Continue.dev

```json
{
  "models": [{
    "provider": "openai",
    "title": "Claude via Gateway",
    "apiBase": "http://localhost:8080/v1",
    "apiKey": "YOUR_API_KEY",
    "model": "claude-sonnet-4-20250514"
  }]
}
```

### LangChain

```python
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    base_url="http://localhost:8080/v1",
    api_key="YOUR_API_KEY",
    model="claude-sonnet-4-20250514",
)
```

## Configuration

All settings use the `CCG_` prefix in `.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `GATEWAY_API_KEY` | `ccg-secret-change-me` | API key for nginx auth |
| `CCG_HOST` | `0.0.0.0` | Server bind address |
| `CCG_PORT` | `8080` | Server port |
| `CCG_DEFAULT_MODEL` | `claude-sonnet-4-20250514` | Default Claude model |
| `CCG_DEFAULT_MAX_TURNS` | `10` | Max conversation turns |
| `CCG_CLAUDE_CLI_TIMEOUT` | `300` | CLI timeout in seconds |

## Managing the Gateway

```bash
# Stop Gateway
docker compose down

# Stop Gateway + disable auto-sync
docker compose down
launchctl unload ~/Library/LaunchAgents/com.claude-gateway.sync-credentials.plist

# Restart Gateway
docker compose up -d
launchctl load ~/Library/LaunchAgents/com.claude-gateway.sync-credentials.plist

# View logs
docker compose logs -f        # Gateway logs
cat logs/sync-credentials.log  # Credential sync logs
```

## Known Limitations

- **No tool calling** -- function/tool calls in the OpenAI format are not supported
- **`temperature` / `max_tokens` ignored** -- accepted in requests but not passed to CLI
- **Token usage always returns 0** -- no token counting implementation
- **One subprocess per request** -- each request spawns a new Claude CLI process
- **No concurrent request limiting** -- heavy load can exhaust system resources
- **No logging** -- add your own logging middleware if needed

## Syncing with Upstream

```bash
git fetch upstream
git merge upstream/main
```

## License

MIT -- see [LICENSE](LICENSE) for details.

Based on [enescingoz/claude-code-gateway](https://github.com/enescingoz/claude-code-gateway).
