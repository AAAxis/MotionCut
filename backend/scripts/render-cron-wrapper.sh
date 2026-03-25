#!/bin/bash
# Wrapper script for the content video batch renderer
# Called by launchd daily or manually
# Logs output to backend/logs/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$BACKEND_DIR/logs"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/render-$(date +%Y-%m-%d).log"

echo "===== Content Video Render: $(date) =====" >> "$LOG_FILE"

cd "$BACKEND_DIR"

# Run the batch renderer for scripts due in the next 2 days
# It auto-skips already-rendered scripts
node scripts/batch-render-content.js 2>&1 >> "$LOG_FILE"

echo "===== Finished: $(date) =====" >> "$LOG_FILE"

# Keep only last 30 days of logs
find "$LOG_DIR" -name "render-*.log" -mtime +30 -delete 2>/dev/null || true
