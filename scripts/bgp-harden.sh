#!/usr/bin/env bash
# BGP hardening on all fabric routers: TCP-MD5 + GTSM (ttl-security hops 1).
# Runtime config via vtysh - lost on fabric redeploy (moved into frr.conf in Part 9).
# Usage: scripts/bgp-harden.sh apply|remove|show
cd "$(dirname "$0")/.."
KEYFILE=labs/fabric/bgp-md5.key
ROUTERS="spine1 spine2 leaf1 leaf2"
ACTION=${1:-show}
case $ACTION in apply|remove|show) ;; *) echo "usage: $0 apply|remove|show"; exit 1 ;; esac

if [ "$ACTION" = apply ] && [ ! -s "$KEYFILE" ]; then
  head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20 > "$KEYFILE"
  chmod 600 "$KEYFILE"
  grep -qx 'labs/fabric/bgp-md5.key' .gitignore 2>/dev/null || echo 'labs/fabric/bgp-md5.key' >> .gitignore
  echo "generated MD5 key in $KEYFILE (gitignored)"
fi

for r in $ROUTERS; do
  C=clab-fabric-$r
  RUN=$(docker exec $C vtysh -c 'show running-config')
  ASN=$(echo "$RUN" | awk '/^router bgp /{print $3; exit}')
  NBRS=$(echo "$RUN" | awk '/^ neighbor [0-9.]+ (remote-as|peer-group)/{print $2}' | sort -u)
  echo "=== $r (AS $ASN) neighbors: $(echo $NBRS) ==="
  if [ -z "$NBRS" ]; then echo "WARNING: no numbered neighbors found on $r - skipping"; continue; fi

  if [ "$ACTION" != show ]; then
    ARGS=(-c 'configure terminal' -c "router bgp $ASN")
    for n in $NBRS; do
      if [ "$ACTION" = apply ]; then
        ARGS+=(-c "neighbor $n password $(cat $KEYFILE)" -c "neighbor $n ttl-security hops 1")
      else
        ARGS+=(-c "no neighbor $n password" -c "no neighbor $n ttl-security hops 1")
      fi
    done
    docker exec $C vtysh "${ARGS[@]}"
  fi
  docker exec $C vtysh -c 'show running-config' \
    | grep -E '^ neighbor [0-9.]+ (password|ttl-security)' \
    | sed -E 's/password .*/password ******/' || echo "(no MD5/GTSM configured)"
done
