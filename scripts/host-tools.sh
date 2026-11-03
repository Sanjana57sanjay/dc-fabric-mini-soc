#!/usr/bin/env bash
# Install test tools on tenant hosts (run after every containerlab deploy)
set -euo pipefail
for h in clab-fabric-host1 clab-fabric-host2; do
  docker exec "$h" apk add --no-cache iperf3 >/dev/null
  echo "$h: $(docker exec "$h" iperf3 --version | head -1)"
done
