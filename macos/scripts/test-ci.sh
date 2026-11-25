#!/bin/bash
# Runs `swift test` with a watchdog: if the tests are still running after $1 seconds (default 420), prints where every thread of the
# test process is stuck (`sample`), kills it and fails, so a hang names its test instead of burning the job's whole timeout.
# The compile comes first and is not timed (the job's timeout covers it): a cold build is minutes, and a watchdog that counted it would kill a slow compile as if it were a hang.
# `swift test` builds again, with nothing left to compile: not `--skip-build`, because only its own build puts Sparkle.framework where the XCTest bundle loads it from, and without it CarrierTests runs 0 tests and fails.
set -uo pipefail
cd "$(dirname "$0")/.."
LIMIT="${1:-420}"
swift build --build-tests --build-system swiftbuild || exit $?
swift test --build-system swiftbuild &
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
