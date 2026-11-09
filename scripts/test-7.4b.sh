#!/usr/bin/env bash
# Part 7.4b: proof for MD5 + GTSM.  Usage: scripts/test-7.4b.sh before|after
# Probe = "legit-looking rogue peer": TCP connect to leaf1:179 FROM spine1's real link IP 10.1.1.0
cd "$(dirname "$0")/.."
TAG=${1:?usage: $0 before|after}

summary() { docker exec clab-fabric-leaf1 vtysh -c 'show bgp summary' | awk '/^Neighbor/{f=1} f && NF>3'; }

echo "=== [$TAG] leaf1 BGP sessions ==="
summary

echo "=== [$TAG] Probe: TCP connect 10.1.1.0 -> 10.1.1.1:179 ==="
(cd attack && docker compose run --rm -T attacker-spine1 python3 -c "
import socket
s = socket.socket(); s.settimeout(4); s.bind(('10.1.1.0', 0))
try:
    s.connect(('10.1.1.1', 179)); print('RESULT: OPEN (handshake accepted without authentication)')
except Exception as e:
    print('RESULT: BLOCKED (%s)' % e)
finally:
    s.close()")

echo "=== [$TAG] TTL of real BGP packets on spine1 eth1 (waits up to 65s for keepalives) ==="
(cd attack && docker compose run --rm -T attacker-spine1 \
   timeout 65 tcpdump -nv -i eth1 -c 4 'tcp port 179' 2>/dev/null) | grep -oE 'ttl [0-9]+' | sort | uniq -c

echo "=== [$TAG] leaf1 sessions after probe (Up/Down must NOT reset) ==="
summary
