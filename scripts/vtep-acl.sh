#!/usr/bin/env bash
# Underlay ACL on the leaves: accept VXLAN (UDP 4789) only from known VTEPs.
# Usage: scripts/vtep-acl.sh apply|remove|show
# Note: rules live in each leaf's netns and are lost on fabric redeploy - re-apply after startup.
cd "$(dirname "$0")/../attack"
VTEPS="10.0.0.11 10.0.0.12"
ACTION=${1:-show}

case $ACTION in
  apply)  CMD="iptables -N VTEP_ACL 2>/dev/null; iptables -F VTEP_ACL;
               for v in $VTEPS; do iptables -A VTEP_ACL -s \$v -j RETURN; done;
               iptables -A VTEP_ACL -j DROP;
               iptables -C INPUT -p udp --dport 4789 -j VTEP_ACL 2>/dev/null \
                 || iptables -I INPUT 1 -p udp --dport 4789 -j VTEP_ACL;
               iptables -L VTEP_ACL -nv" ;;
  remove) CMD="iptables -D INPUT -p udp --dport 4789 -j VTEP_ACL 2>/dev/null;
               iptables -F VTEP_ACL 2>/dev/null; iptables -X VTEP_ACL 2>/dev/null; echo removed" ;;
  show)   CMD="iptables -L VTEP_ACL -nv 2>/dev/null || echo 'no VTEP_ACL chain'" ;;
  *) echo "usage: $0 apply|remove|show"; exit 1 ;;
esac

for leaf in leaf1 leaf2; do
  echo "=== $leaf: $ACTION ==="
  docker compose run --rm -T admin-$leaf sh -c "$CMD"
done
