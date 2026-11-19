#!/usr/bin/env bash
# Samples the memory of one running Carrier app over time: its footprint, the bytes malloc holds alive and its RSS, every <interval> seconds,
# and a `heap` listing at the start and at the end to compare by class. It only reads: it never signals a process.
# Pass a PID you captured (never look one up by name: the installed Carrier's processes have the same names).
# A steady rise in the live malloc bytes with the app idle is a leak or a pool that never drains; the diff of the two listings says of what.
# usage: mem-loop.sh <app-pid> <seconds> <interval> <output-prefix>   (writes <prefix>.csv, <prefix>.heap0.txt and <prefix>.heapN.txt)
set -euo pipefail
pid=${1:?usage: mem-loop.sh <app-pid> <seconds> <interval> <output-prefix>}
duration=${2:?seconds}
interval=${3:?interval}
out=${4:?output prefix}
[[ "$duration" =~ ^[1-9][0-9]*$ && "$interval" =~ ^[1-9][0-9]*$ ]] || { echo "error: seconds and interval must be whole numbers above 0" >&2; exit 1; }
heap "$pid" > "$out.heap0.txt" 2>&1 || true
echo "t,footprint_MB,malloc_alive_MB,rss_MB" > "$out.csv"
start=$(date +%s)
while kill -0 "$pid" 2>/dev/null; do
  t=$(( $(date +%s) - start ))
  summary=$(vmmap -summary "$pid" 2>/dev/null || true)
  footprint=$(echo "$summary" | awk '/^Physical footprint:/ { gsub("M", "", $3); print $3 }')
  alive=$(echo "$summary" | awk '/^TOTAL/ && /%/ { gsub("M", "", $7); print $7 }' | tail -n 1)
  rss=$(ps -o rss= -p "$pid" | awk '{ printf "%.1f", $1 / 1024 }')
  echo "$t,$footprint,$alive,$rss" >> "$out.csv"
  (( t >= duration )) && break
  sleep "$interval"
done
heap "$pid" > "$out.heapN.txt" 2>&1 || true
