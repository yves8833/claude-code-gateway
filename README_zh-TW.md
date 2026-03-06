# Claude Code Gateway

> **免責聲明：** 本專案**不會**提取或使用 OAuth token。它在 Docker 容器中以子程序方式執行官方 Claude Code CLI。這仍可能不符合 Anthropic 對 Claude Code 訂閱的預期用途。使用前請參閱 [Anthropic 消費者服務條款](https://www.anthropic.com/legal/consumer-terms)。**風險自負。**

> 將你的 Claude Code 訂閱轉換為安全的 API 端點，供任何 AI 工具使用——不需要額外購買 Anthropic API key。

## 這是什麼？

Claude Code Gateway 是一個 Python FastAPI 伺服器，將 Claude Code CLI 封裝為 OpenAI 相容 API。它提供 `/v1/chat/completions` 端點，讓任何支援 OpenAI 格式的工具都能透過你現有的訂閱使用 Claude 模型，無需按 token 計費。

本 fork 新增了 **nginx 反向代理**搭配 API key 認證與安全強化。

## 架構

```
客戶端 (Cline / Aider / Langfuse / Immersive Translate / ...)
  │  Authorization: Bearer <GATEWAY_API_KEY>
  ▼
nginx (127.0.0.1:8080 HTTP / :8443 HTTPS)
  │  ├─ /health → 免認證
  │  ├─ CORS headers（支援瀏覽器擴充功能）
  │  └─ /* → 驗證 Bearer token
  ▼
FastAPI (api:8080，僅內部存取)
  │  ├─ POST /v1/chat/completions → Claude CLI 子程序
  │  ├─ GET  /v1/models → 模型清單
  │  └─ GET  /health → 健康檢查
  ▼
Claude Code CLI (Node.js)
  └─ 透過 ~/.claude/.credentials.json 認證
```

## 快速開始

### 1. 複製並設定

```bash
git clone https://github.com/yves8833/claude-code-gateway.git
cd claude-code-gateway
cp .env.example .env
```

### 2. 設定 API Key

編輯 `.env`，加入你的 Gateway API key：

```bash
# 產生隨機 key
echo "GATEWAY_API_KEY=ccg-$(openssl rand -hex 16)" >> .env
```

或自訂：

```
GATEWAY_API_KEY=your-secret-key-here
```

### 3. 同步 Claude CLI 憑證

新版 Claude CLI 將憑證儲存在 macOS Keychain 而非檔案。內建的同步腳本會將憑證匯出供 Docker 使用：

```bash
# 首次使用：執行 claude 完成登入流程（如果還沒登入的話）
claude

# 從 Keychain 同步憑證到檔案
./scripts/sync-credentials.sh
```

啟用自動同步（每小時 + 登入時自動執行）：

```bash
# 安裝 LaunchAgent
cp scripts/com.claude-gateway.sync-credentials.plist ~/Library/LaunchAgents/
# 如果專案路徑不同，請先編輯 plist 更新路徑
launchctl load ~/Library/LaunchAgents/com.claude-gateway.sync-credentials.plist
```

管理 LaunchAgent：

```bash
# 查看狀態
launchctl list | grep claude-gateway

# 手動觸發同步
./scripts/sync-credentials.sh

# 查看日誌
cat logs/sync-credentials.log

# 停用自動同步
launchctl unload ~/Library/LaunchAgents/com.claude-gateway.sync-credentials.plist
```

### 4. 產生 HTTPS 憑證（選用，建議啟用）

```bash
# 安裝 mkcert（macOS）
brew install mkcert
mkcert -install

# 產生受信任的本地憑證
mkdir -p certs
mkcert -cert-file certs/localhost.pem -key-file certs/localhost-key.pem localhost 127.0.0.1
```

### 5. 啟動

```bash
docker compose up --build -d
```

驗證：

```bash
# 健康檢查（不需認證）
curl http://localhost:8080/health

# 測試 HTTP
curl http://localhost:8080/v1/models \
  -H "Authorization: Bearer YOUR_API_KEY"

# 測試 HTTPS
curl https://localhost:8443/v1/models \
  -H "Authorization: Bearer YOUR_API_KEY"
```

## 安全性

本 fork 在原始專案之上新增多層安全保護：

| 層級 | 說明 |
|------|------|
| **nginx 反向代理** | API 服務不直接對外暴露 |
| **HTTPS (TLS)** | Port 8443，使用 mkcert 受信任憑證 |
| **API key 認證** | 所有請求需附帶 `Authorization: Bearer <key>` |
| **CORS** | 支援瀏覽器擴充功能（如沉浸式翻譯）連線 |
| **localhost 綁定** | `127.0.0.1:8080/:8443`——外部網路無法存取 |
| **最小化憑證掛載** | 僅掛載 `.credentials.json`，非整個 `~/.claude` 目錄 |
| **憑證自動同步** | LaunchAgent 每小時同步 Keychain → 檔案，變更時自動重啟容器 |
| **Health 端點免認證** | `/health` 無需 API key，方便監控 |

### 為什麼只掛載最小憑證？

掛載整個 `~/.claude` 目錄會導致 CLI 因 task lock 檔案、plugin 設定和 MCP server 定義而卡住。僅掛載 `.credentials.json` 可修復此問題並減少攻擊面。

## 可用模型

任何 `claude-*` 模型名稱都會直接傳遞給 CLI。GPT 模型名稱會自動對應。

| 模型 | ID |
|------|----|
| Claude Sonnet 4 | `claude-sonnet-4-20250514` |
| Claude Sonnet 4.6 | `claude-sonnet-4-6` |
| Claude Opus 4 | `claude-opus-4-20250514` |
| Claude Opus 4.6 | `claude-opus-4-6` |
| Claude Haiku 4.5 | `claude-haiku-4-5-20251001` |

簡寫別名：`sonnet`、`opus`、`haiku`
GPT 別名：`gpt-4o` → Sonnet 4、`gpt-3.5-turbo` → Haiku 4.5

## 平台整合

通用設定：

| 設定項 | 值 |
|--------|-----|
| **Base URL (HTTP)** | `http://localhost:8080/v1` |
| **Base URL (HTTPS)** | `https://localhost:8443/v1` |
| **API Key** | 你的 `GATEWAY_API_KEY` 值 |
| **Adapter / Provider** | OpenAI |

> 從其他 Docker 容器連線，使用 `http://host.docker.internal:8080/v1` 作為 Base URL。
> 瀏覽器擴充功能需使用 HTTPS：`https://localhost:8443/v1`。

### 沉浸式翻譯（瀏覽器擴充功能）

在沉浸式翻譯設定中，選擇 **OpenAI Custom** 服務：

- API URL：`https://localhost:8443/v1/chat/completions`
- API Key：你的 `GATEWAY_API_KEY`
- 模型：`claude-haiku-4-5-20251001`（翻譯推薦用 Haiku，速度快且品質足夠）

> 瀏覽器擴充功能必須使用 HTTPS（port 8443），HTTP 會因安全限制而失敗。

### Langfuse

在 Langfuse Settings → LLM Connections：

- Provider name：`claude-gateway`
- Adapter：`openai`
- Base URL：`http://host.docker.internal:8080/v1`（Langfuse 在 Docker 內，用 HTTP 即可）
- API Key：你的 `GATEWAY_API_KEY`
- Custom models：`claude-sonnet-4-20250514`、`claude-opus-4-6` 等

### Cline

在 Cline 設定中，API Provider 選 "OpenAI Compatible"：

- Base URL：`http://localhost:8080/v1`
- API Key：你的 `GATEWAY_API_KEY`
- Model：`claude-sonnet-4-20250514`

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

## 設定參數

所有設定使用 `CCG_` 前綴，定義在 `.env` 中：

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `GATEWAY_API_KEY` | `ccg-secret-change-me` | nginx 認證用 API key |
| `CCG_HOST` | `0.0.0.0` | 伺服器綁定地址 |
| `CCG_PORT` | `8080` | 伺服器連接埠 |
| `CCG_DEFAULT_MODEL` | `claude-sonnet-4-20250514` | 預設 Claude 模型 |
| `CCG_DEFAULT_MAX_TURNS` | `10` | 最大對話回合數 |
| `CCG_CLAUDE_CLI_TIMEOUT` | `300` | CLI 逾時秒數 |

## 已知限制

- **不支援 tool calling**——OpenAI 格式的 function/tool call 不支援
- **`temperature` / `max_tokens` 被忽略**——請求中接受但不會傳給 CLI
- **Token 用量永遠回傳 0**——無 token 計數實作
- **每次請求一個子程序**——每個請求都會啟動新的 Claude CLI 程序
- **無並發請求限制**——高負載可能耗盡系統資源
- **無日誌記錄**——如需要請自行加入 logging middleware

## 同步上游更新

```bash
git fetch upstream
git merge upstream/main
```

## 授權

MIT——詳見 [LICENSE](LICENSE)。

基於 [enescingoz/claude-code-gateway](https://github.com/enescingoz/claude-code-gateway)。
