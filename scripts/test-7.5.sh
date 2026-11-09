#!/usr/bin/env bash
# Part 7.5: rate-limited ICMP/UDP flood ladder host1 -> host2.
# Measures detection (9000006/9000007) and sensor capacity (kernel drops) per rate.
cd "$(dirname "$0")/.."
EVE=ids/logs/leaf1/eve.json
DST=192.168.10.12
DUR=10
RATES="200 1000 2000"
sudo -v

cnt() { sudo grep -ac "\"signature_id\":$1" $EVE; }
cap() { sudo grep -a '"event_type":"stats"' $EVE | tail -1 \
          | grep -oE '"kernel_(packets|drops)":[0-9]+' | head -2 | cut -d: -f2 | tr '\n' ' '; }
mem() { docker stats --no-stream --format '{{.MemUsage}}' ids-suricata-leaf1 | cut -d/ -f1; }
flood() {  # $1=icmp|udp  $2=rate
  local OPT; [ "$1" = icmp ] && OPT="--icmp" || OPT="--udp -p 9999"
  (cd attack && docker compose run --rm -T attacker-host1 \
     nping $OPT --rate $2 -c $(( $2 * DUR )) -q $DST) \
     | grep -oE 'sent: [0-9]+|in [0-9.]+ seconds' | tr '\n' ' '
}

echo "=== Negative test: normal ping (10 packets @ 1/s) ==="
B=$(cnt 9000006)
docker exec clab-fabric-host1 ping -c 10 -i 1 -q $DST | grep -E 'transmitted'
sleep 10
echo "9000006 new alerts: $(( $(cnt 9000006) - B ))  (expected 0)"

echo
printf "%-5s %-5s | %-6s | %-8s %-7s | %-9s | %s\n" proto pps alerts captured drops suri_mem "nping actual"
printf -- '-%.0s' {1..80}; echo
for P in icmp udp; do
  SID=$([ "$P" = icmp ] && echo 9000006 || echo 9000007)
  for R in $RATES; do
    read KP1 KD1 < <(cap); A1=$(cnt $SID)
    OUT=$(flood $P $R)
    sleep 12   # wait for a fresh stats record (written every ~8s)
    read KP2 KD2 < <(cap); A2=$(cnt $SID)
    printf "%-5s %-5s | %-6s | %-8s %-7s | %-9s | %s\n" \
      $P $R $((A2-A1)) $((KP2-KP1)) $((KD2-KD1)) "$(mem)" "$OUT"
    if ! docker inspect -f '{{.State.Running}}' ids-suricata-leaf1 | grep -q true; then
      echo "Suricata stopped - aborting ladder"; exit 1
    fi
  done
done
