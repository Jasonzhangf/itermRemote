#!/usr/bin/env bash
# Check Flutter app logs for overflow errors and other issues
# Usage: scripts/check_app_logs.sh <log_file>

set -euo pipefail

LOG_FILE="${1:-/tmp/itermremote_console.log}"

if [ ! -f "$LOG_FILE" ]; then
  echo "❌ Log file not found: $LOG_FILE"
  echo "💡 Start app with: flutter run -d macos --debug 2>&1 | tee $LOG_FILE"
  exit 1
fi

echo "🔍 Checking logs: $LOG_FILE"
echo "─────────────────────────────────────"

# Count errors (use || true to avoid exit on no match)
OVERFLOW_COUNT=$(grep -c "overflowed" "$LOG_FILE" 2>/dev/null || echo 0)
RENDER_FLEX_COUNT=$(grep -c "RenderFlex" "$LOG_FILE" 2>/dev/null || echo 0)
ASSERTION_COUNT=$(grep -c "assertion was thrown" "$LOG_FILE" 2>/dev/null || echo 0)

# Trim whitespace and newlines from grep output
OVERFLOW_COUNT=$(echo "$OVERFLOW_COUNT" | tr -d '[:space:]')
RENDER_FLEX_COUNT=$(echo "$RENDER_FLEX_COUNT" | tr -d '[:space:]')
ASSERTION_COUNT=$(echo "$ASSERTION_COUNT" | tr -d '[:space:]')

# Ensure numeric values
OVERFLOW_COUNT=${OVERFLOW_COUNT:-0}
RENDER_FLEX_COUNT=${RENDER_FLEX_COUNT:-0}
ASSERTION_COUNT=${ASSERTION_COUNT:-0}

TOTAL_ERRORS=$((OVERFLOW_COUNT + RENDER_FLEX_COUNT + ASSERTION_COUNT))

echo "📊 Error Summary:"
echo "   - Overflow errors:    $OVERFLOW_COUNT"
echo "   - RenderFlex issues:  $RENDER_FLEX_COUNT"
echo "   - Assertions:         $ASSERTION_COUNT"
echo "   - Total:              $TOTAL_ERRORS"
echo "─────────────────────────────────────"

if [ "$TOTAL_ERRORS" -gt 0 ]; then
  echo ""
  echo "❌ FOUND $TOTAL_ERRORS ERROR(S) - MUST FIX BEFORE CONTINUING"
  echo ""
  
  # Show first few overflow errors
  if [ "$OVERFLOW_COUNT" -gt 0 ]; then
    echo "🔴 Overflow Details:"
    grep -A 2 "overflowed" "$LOG_FILE" | head -20 || true
    echo ""
  fi
  
  # Show assertions
  if [ "$ASSERTION_COUNT" -gt 0 ]; then
    echo "🔴 Assertion Details:"
    grep -A 3 "assertion was thrown" "$LOG_FILE" | head -20 || true
    echo ""
  fi
  
  exit 1
else
  echo "✅ No errors found in logs"
  exit 0
fi
