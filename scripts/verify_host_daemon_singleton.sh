#!/usr/bin/env bash
# Verify host_daemon start/stop does not leak processes
set -euo pipefail

ITERATIONS=${1:-3}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/tmp/itermremote-daemon-verify"
mkdir -p "$LOG_DIR"

function count_daemon_procs() {
  pgrep -f "host_daemon.app/Contents/MacOS/host_daemon" | wc -l | tr -d ' '
}

function check_orphans() {
  local count
  count=$(count_daemon_procs)
  if [ "$count" -gt 1 ]; then
    echo "❌ Orphaned host_daemon processes detected: $count" | tee -a "$LOG_DIR/verify.log"
    pgrep -fl "host_daemon.app/Contents/MacOS/host_daemon" | tee -a "$LOG_DIR/verify.log"
    return 1
  fi
  return 0
}

echo "[verify] Host daemon singleton check" | tee "$LOG_DIR/verify.log"

echo "[verify] Initial stop" | tee -a "$LOG_DIR/verify.log"
bash "$SCRIPT_DIR/stop_host_daemon.sh" 2>/dev/null || true
sleep 1
check_orphans || exit 1

for i in $(seq 1 "$ITERATIONS"); do
  echo "[verify] Iteration $i start" | tee -a "$LOG_DIR/verify.log"
  bash "$SCRIPT_DIR/start_host_daemon.sh" --log-file="$LOG_DIR/host_daemon_$i.log"
  sleep 2
  check_orphans || exit 1

  echo "[verify] Iteration $i stop" | tee -a "$LOG_DIR/verify.log"
  bash "$SCRIPT_DIR/stop_host_daemon.sh" 2>/dev/null || true
  sleep 2
  check_orphans || exit 1

done

echo "✅ Host daemon singleton verification passed" | tee -a "$LOG_DIR/verify.log"
