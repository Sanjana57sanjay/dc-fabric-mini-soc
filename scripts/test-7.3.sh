#!/usr/bin/env bash
# Part 7.3: VXLAN injection from a non-VTEP source into VNI 10010.
# Q1: does Suricata alert?  Q2: does leaf1 deliver the fake frame to host1?
# host1 is plain Alpine (BusyBox ip has no -br), so lookups run in the attacker-host1 sidecar.
cd "$(dirname "$0")/.."
EVE=ids/logs/leaf1/eve.json
ROGUE=172.31.99.98
VTEP=10.0.0.11
sudo -v

echo "=== Rule 9000003 ==="
grep -a 'sid:9000003' ids/suricata/rules/local.rules

echo "=== leaf1 VXLAN device + rp_filter ==="
docker exec clab-fabric-leaf1 ip -d link show vxlan10010 | grep -oE 'vxlan id [0-9]+.*' | cut -c1-90
docker exec clab-fabric-leaf1 sh -c 'for i in all eth1 eth2; do echo "rp_filter $i = $(cat /proc/sys/net/ipv4/conf/$i/rp_filter)"; done'

HIF=$(cd attack && docker compose run --rm -T attacker-host1 ip -br -4 addr 2>/dev/null \
      | awk '/192\.168\.10\.11/{print $1}' | cut -d@ -f1)
HMAC=$(cd attack && docker compose run --rm -T attacker-host1 cat /sys/class/net/$HIF/address 2>/dev/null)
echo "host1 tenant interface: '$HIF'  MAC: '$HMAC'"
if [ -z "$HIF" ] || [ -z "$HMAC" ]; then
  echo "ERROR: could not find host1's tenant interface/MAC - stopping (nothing was sent)."
  exit 1
fi

S1=$(sudo stat -c %s $EVE)

echo "=== Start capture inside host1, then inject from spine1 ==="
(cd attack && docker compose run --rm -T attacker-host1 \
   timeout 15 tcpdump -ni $HIF -c 3 'icmp and host 192.168.10.66') > /tmp/7.3-host1.txt 2>&1 &
sleep 4
(cd attack && docker compose run --rm -T -v "$PWD/scapy:/scapy:ro" attacker-spine1 \
   python3 /scapy/vxlan_inject.py $ROGUE $VTEP $HMAC)
wait
sleep 5

echo "=== Q2: did the fake frame reach host1? ==="
grep -E 'ICMP|captured' /tmp/7.3-host1.txt || { echo "nothing captured in host1. Raw tcpdump output:"; cat /tmp/7.3-host1.txt; }

echo "=== Q1: new Suricata alerts since injection ==="
N=0
while read -r l; do
  N=$((N+1))
  echo "$l" | grep -oE '"(signature_id|signature|src_ip|dest_ip|dest_port)":("[^"]*"|[0-9]+)' | sort -u | tr '\n' ' '
  echo
done < <(sudo tail -c +$((S1+1)) $EVE | grep -a '"event_type":"alert"')
echo "total new alerts: $N"
