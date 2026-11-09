#!/usr/bin/env bash
# Part 7.2: rogue BGP peer - spoofed TCP SYN to leaf1:179 from a non-underlay source
# Sent from spine1's namespace, so it arrives on a leaf1 uplink that Suricata sniffs.
# nping shows Rcvd: 0 by design: replies go to the spoofed address, not to spine1.
cd "$(dirname "$0")/.."
EVE=ids/logs/leaf1/eve.json
ROGUE=172.31.99.99
count() { sudo grep -ac '"signature_id":9000002' $EVE; }
bgp()   { docker exec clab-fabric-leaf1 vtysh -c 'show bgp summary' | awk '/^Neighbor/{f=1} f && NF>3'; }

sudo -v   # ask for the sudo password once, up front

echo "=== Path from spine1 to leaf1 ==="
ROUTE=$(cd attack && docker compose run --rm -T attacker-spine1 ip route get 10.0.0.11 2>/dev/null | head -1)
echo "$ROUTE"
TARGET=$(echo "$ROUTE" | grep -oE 'via [0-9.]+' | awk '{print $2}')
TARGET=${TARGET:-10.0.0.11}
echo "target leaf1 address: $TARGET"

echo "=== BGP sessions BEFORE ==="
bgp

B=$(count); echo "9000002 alerts before: $B"

echo "=== Sending 3 spoofed SYNs $ROGUE -> $TARGET:179 ==="
(cd attack && docker compose run --rm -T attacker-spine1 \
  nping --tcp -p 179 --flags syn -S $ROGUE -c 3 --rate 1 $TARGET) | grep -E 'SENT|Raw packets'
sleep 5

A=$(count); echo "9000002 alerts after: $A  (new: $((A - B)), expected 1-3)"

echo "=== Newest 9000002 alert ==="
sudo grep -a '"signature_id":9000002' $EVE | tail -1 \
  | grep -oE '"(timestamp|in_iface|src_ip|dest_ip|dest_port|signature)":[^,}]*' | sort -u

echo "=== BGP sessions AFTER (Up/Down times should keep counting, not reset) ==="
bgp
