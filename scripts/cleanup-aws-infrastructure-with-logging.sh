#!/bin/bash
# Wrapper script for cleanup-aws-infrastructure.sh with logging
# Usage: ./cleanup-aws-infrastructure-with-logging.sh
#
# This wrapper:
# 1. Preserves interactive input (read prompts work normally)
# 2. Captures all output to log file
# 3. Automatically sanitizes sensitive data
# 4. Keeps only last 10 logs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/../logs"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RAW_LOG="$LOG_DIR/cleanup-${TIMESTAMP}-raw.log"
FINAL_LOG="$LOG_DIR/cleanup-${TIMESTAMP}.log"

echo "================================================"
echo "AWS 基礎設施清理 (帶日誌記錄)"
echo "================================================"
echo ""
echo "日誌將儲存至: $FINAL_LOG"
echo ""

# Use process substitution to tee output while preserving stdin
{
  "$SCRIPT_DIR/cleanup-aws-infrastructure.sh"
} 2>&1 | tee "$RAW_LOG"

EXIT_CODE=${PIPESTATUS[0]}

# Sanitize the log
echo ""
echo "處理日誌（脫敏中）..."

# Remove ANSI color codes and sanitize sensitive data
sed -E \
  -e 's/\x1b\[[0-9;]*m//g' \
  -e 's/(password|Password|PASSWORD)[=:][^ \t]*/\1=***REDACTED***/g' \
  -e 's/(AKIA[A-Z0-9]{16})/***REDACTED_ACCESS_KEY***/g' \
  -e 's/([0-9]{12}\.dkr\.ecr\.)/***ACCOUNT***.dkr.ecr./g' \
  "$RAW_LOG" > "$FINAL_LOG"

rm "$RAW_LOG"

echo "✓ 日誌已儲存並脫敏: $FINAL_LOG"

# Cleanup old logs (keep last 10)
echo ""
echo "清理舊日誌..."
ls -t "$LOG_DIR"/cleanup-*.log 2>/dev/null | tail -n +11 | xargs -r rm || true
echo "✓ 保留最近 10 個日誌"

exit $EXIT_CODE
