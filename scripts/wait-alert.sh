#!/usr/bin/env bash
# Wait until alert-sink logs a line matching a pattern; prints progress and how long it took.
# Usage: scripts/wait-alert.sh "<regex>" [max_seconds=300] [since=now (UTC ISO time)]
PAT=$1; MAX=${2:-300}; START=${3:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
t0=$(date +%s)
echo "waiting up to ${MAX}s for: $PAT   (progress every 30s - do not press Ctrl-C)"
while :; do
  L=$(docker logs --since "$START" alert-sink 2>&1 | grep -E "$PAT" | tail -1)
  T=$(( $(date +%s) - t0 ))
  if [ -n "$L" ]; then echo "OK after ${T}s -> $L"; exit 0; fi
  if [ "$T" -ge "$MAX" ]; then
    echo "TIMEOUT after ${MAX}s. Last alert-sink lines:"
    docker logs --since "$START" alert-sink 2>&1 | tail -5
    exit 1
  fi
  [ $(( T % 30 )) -lt 5 ] && [ "$T" -gt 0 ] && echo "  ...${T}s, still waiting"
  sleep 5
done
