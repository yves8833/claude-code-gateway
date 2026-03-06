#!/bin/bash
# Sync Claude Code credentials from macOS Keychain to file for Docker mount.
# Runs as a LaunchAgent every hour, or manually before docker compose up.

set -euo pipefail

CRED_FILE="$HOME/.claude/.credentials.json"
KEYCHAIN_SERVICE="Claude Code-credentials"
COMPOSE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Extract credentials from Keychain
cred=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null) || {
    echo "[sync-credentials] Keychain entry not found. Is Claude CLI logged in?" >&2
    exit 1
}

# Compare with existing file (avoid unnecessary writes)
if [ -f "$CRED_FILE" ]; then
    existing=$(cat "$CRED_FILE" 2>/dev/null || echo "")
    if [ "$cred" = "$existing" ]; then
        exit 0
    fi
fi

# Write new credentials
echo "$cred" > "$CRED_FILE"
chmod 600 "$CRED_FILE"
echo "[sync-credentials] $(date '+%Y-%m-%d %H:%M:%S') Credentials synced to $CRED_FILE"

# Restart Gateway API container if running (pick up new credentials)
if docker compose -f "$COMPOSE_DIR/docker-compose.yml" ps --status running api 2>/dev/null | grep -q api; then
    docker compose -f "$COMPOSE_DIR/docker-compose.yml" restart api 2>/dev/null
    echo "[sync-credentials] Gateway API container restarted"
fi
