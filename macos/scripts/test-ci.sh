#!/bin/bash
# Runs `swift test` with a watchdog: if it is still running after $1 seconds (default 420), prints where every thread of the
# test process is stuck (`sample`), kills it and fails, so a hang names its test instead of burning the job's whole timeout.
set -uo pipefail
cd "$(dirname "$0")/.."
LIMIT="${1:-420}"
swift test &
PID=$!
for ((i = 0; i < LIMIT; i++)); do
  kill -0 "$PID" 2>/dev/null || { wait "$PID"; exit $?; }
  sleep 1
done
echo "test-ci: swift test is still running after ${LIMIT}s, sampling it"
for P in $(pgrep -f "swiftpm-testing|xctest"); do
  echo "=== sample of $P ($(ps -o command= -p "$P" | cut -c1-120))"
  sample "$P" 5 -file "/tmp/sample-$P.txt" >/dev/null 2>&1 && cat "/tmp/sample-$P.txt"
done
pkill -P "$PID" 2>/dev/null; kill "$PID" 2>/dev/null
exit 1
