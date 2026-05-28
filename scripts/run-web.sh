#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

# Load env vars, exporting them so the Node process sees them
set -a
source "$ENV_FILE"
set +a

# Also load local-env.sh (which handles defaults like LOCAL_UPLOAD_BASE_URL)
source "$PROJECT_DIR/scripts/local-env.sh"

# Kill any existing nohup/foreground next processes on port 3000
# (launchd will restart this script via KeepAlive, so a stale process from
# a previous manual `pnpm dev:web` or `next start` would block the port)
lsof -ti :3000 2>/dev/null | xargs kill 2>/dev/null || true

cd "$PROJECT_DIR/apps/web"
exec node_modules/.bin/next start --port 3000