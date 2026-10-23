#!/bin/sh
# Usage: setup-evpn.sh <local-vtep-ip>
# Builds: eth3 (host port) + vxlan10010 -> bridge br10
set -e
VTEP_IP="$1"
VNI=10010

# Bridge = the "VLAN 10 switch" inside the leaf
ip link add br10 type bridge

# VXLAN tunnel interface, sourced from the loopback (VTEP)
ip link add vxlan$VNI type vxlan id $VNI local $VTEP_IP dstport 4789 nolearning
ip link set vxlan$VNI mtu 1500
ip link set vxlan$VNI master br10
# EVPN installs remote MACs, so the bridge must not learn them from the tunnel
ip link set dev vxlan$VNI type bridge_slave learning off

# Host-facing port
ip link set eth3 mtu 1500
ip link set eth3 master br10

ip link set br10 up
ip link set vxlan$VNI up
ip link set eth3 up
echo "EVPN data plane ready: VNI $VNI, VTEP $VTEP_IP"
