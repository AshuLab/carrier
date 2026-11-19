#!/usr/bin/env bash
# Samples one running Carrier app and, when given, a chat host and its children: CPU, idle wake-ups and energy from `top`, the app's
# footprint, and the host's process tree with its RSS. It only reads: it never signals a process. Pass PIDs you captured or the person
# gave you; never look one up by name (the installed Carrier's processes have the same names).
# usage: perf-sample.sh <app-pid> [chat-host-pid] [seconds=30]
set -euo pipefail
app=${1:?usage: perf-sample.sh <app-pid> [chat-host-pid] [seconds]}
host=${2:-}
seconds=${3:-30}
echo "## app $app over ${seconds}s"
# the first sample of top has no deltas for the CPU: take two and keep the last line. `idlew` and `csw` are totals since the process
# started, so what the window sampled is the difference between the two samples
samples=$(top -l 2 -s "$seconds" -pid "$app" -stats pid,command,cpu,idlew,power,csw | grep -E "^$app ")
echo "$samples" | tail -n 1 | awk '{print $1, $2, $3, $4, $5}'
echo "$samples" | awk -v seconds="$seconds" '
  { gsub(/[+-]/, "", $4); gsub(/[+-]/, "", $6); idle[NR] = $4; csw[NR] = $6 }
  END {
    if (NR == 2) {
      printf "idle wake-ups per second over the window: %.1f\n", (idle[2] - idle[1]) / seconds
      printf "context switches per second over the window: %.1f\n", (csw[2] - csw[1]) / seconds
    }
  }'
footprint "$app" 2>/dev/null | grep -m 1 "Footprint" || echo "footprint: not available"
if [[ -n "$host" ]]; then
  echo "## chat host $host and its children"
  ps -A -o pid=,ppid=,rss=,comm= | awk -v root="$host" '
    { pid[NR] = $1; ppid[NR] = $2; rss[NR] = $3; $1 = $2 = $3 = ""; comm[NR] = $0 }
    END {
      keep[root] = 1
      do { grew = 0; for (i = 1; i <= NR; i++) if (keep[ppid[i]] && !keep[pid[i]]) { keep[pid[i]] = 1; grew = 1 } } while (grew)
      for (i = 1; i <= NR; i++) if (keep[pid[i]]) { n++; total += rss[i]; printf "%7d %8d KB%s\n", pid[i], rss[i], comm[i] }
      printf "processes %d, rss %.1f MB\n", n, total / 1024
    }'
fi
