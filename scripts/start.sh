#!/usr/bin/env bash
# dc-fabric-mini-soc: full startup after a VM reboot (or a clean redeploy).
# Order matters: the IDS must be recreated AFTER the fabric, or it watches a stale namespace.
set -u
cd "$(dirname "$0")/.."
EVE=ids/logs/leaf1/eve.json
step() { echo; echo "=== [$1] $2 ==="; }

bgp_up() {  # $1=router: number of established rows in 'show bgp summary'
  docker exec clab-fabric-$1 vtysh -c 'show bgp summary' 2>/dev/null \
    | awk '/^Neighbor/{f=1;next} f && NF>3 && $NF ~ /^[0-9]+$/' | wc -l
}
wait_bgp() {
  for i in $(seq 1 24); do
    L1=$(bgp_up leaf1); L2=$(bgp_up leaf2)
    [ "$L1" -ge 2 ] && [ "$L2" -ge 2 ] && { echo "BGP established (leaf1=$L1 leaf2=$L2 rows) after $((i*5))s"; return 0; }
    sleep 5
  done
  echo "WARNING: BGP not fully established after 120s (leaf1=$L1 leaf2=$L2)"; return 1
}

sudo -v
T0=$(date +%s)

step 1/7 "Fabric (containerlab deploy --reconfigure)"
if sudo containerlab deploy -t labs/fabric/fabric.clab.yml --reconfigure > /tmp/clab-deploy.log 2>&1; then
  echo "fabric deployed ($(grep -c 'clab-fabric-' /tmp/clab-deploy.log) node lines)"
else
  tail -20 /tmp/clab-deploy.log; echo "FATAL: fabric deploy failed"; exit 1
fi

step 2/7 "Monitoring stack"
(cd monitoring && docker compose up -d 2>&1 | tail -5)
docker start alert-sink >/dev/null 2>&1 && echo "alert-sink running"

step 3/7 "IDS (force-recreate: attach to the NEW leaf1 namespace)"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
(cd ids && docker compose up -d --force-recreate 2>&1 | tail -3)

step 4/7 "Host tools"
./scripts/host-tools.sh

step 5/7 "Wait for BGP (before hardening)"
wait_bgp

step 6/7 "Hardening: VTEP ACL + BGP MD5/GTSM"
./scripts/vtep-acl.sh apply > /tmp/vtep-acl.log 2>&1 && echo "VTEP ACL applied on leaf1+leaf2" || { cat /tmp/vtep-acl.log; echo "WARNING: VTEP ACL failed"; }
./scripts/bgp-harden.sh apply > /tmp/bgp-harden.log 2>&1
echo "MD5/GTSM lines configured: $(grep -cE 'password \*+|ttl-security' /tmp/bgp-harden.log) (expect 16: 4 routers x 2 neighbors x 2)"
wait_bgp

step 7/7 "Health check"
FAIL=0
chk() { if "$2" >/dev/null 2>&1; then echo "PASS  $1"; else echo "FAIL  $1"; FAIL=1; fi; }
c_ping()     { docker exec clab-fabric-host1 ping -c 2 -W 1 192.168.10.12; }
c_engine()   { for i in $(seq 1 12); do docker logs --since "$TS" ids-suricata-leaf1 2>&1 | grep -q 'Engine started' && return 0; sleep 5; done; return 1; }
c_ifaces()   { ! docker logs --since "$TS" ids-suricata-leaf1 2>&1 | grep -q 'No such device'; }
c_eve()      { s1=$(sudo stat -c %s $EVE); sleep 12; [ "$(sudo stat -c %s $EVE)" -gt "$s1" ]; }
c_md5()      { docker exec clab-fabric-leaf1 vtysh -c 'show running-config' | grep -q ' password '; }
c_acl()      { (cd attack && docker compose run --rm -T admin-leaf1 iptables -L VTEP_ACL -n) | grep -q DROP; }
c_grafana()  { curl -sf http://localhost:3000/api/health; }
c_local()    { ! ss -ltn | grep -qE '(0\.0\.0\.0|\*|\[::\]):3000\s'; }
c_sink()     { docker inspect -f '{{.State.Running}}' alert-sink | grep -q true; }

chk "tenant ping host1 -> host2 across VXLAN"   c_ping
chk "Suricata engine started"                   c_engine
chk "Suricata sees eth1/eth2 (no 'No such device')" c_ifaces
chk "eve.json is being written"                 c_eve
chk "BGP MD5 configured on leaf1"               c_md5
chk "VTEP ACL active on leaf1"                  c_acl
chk "Grafana healthy"                           c_grafana
chk "Grafana bound to localhost only"           c_local
chk "alert-sink running"                        c_sink

echo
echo "startup finished in $(( $(date +%s) - T0 ))s"
[ "$FAIL" -eq 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED - see above"
exit $FAIL
