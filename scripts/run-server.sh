#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
LOG_DIR="$HOME/.multica"

mkdir -p "$LOG_DIR"

# Load env vars, exporting them so the Go binary sees them
set -a
source "$ENV_FILE"
set +a

cd "$PROJECT_DIR"
exec server/bin/server
