# Lightweight attacker toolbox for Part 7 (ARM64-friendly)
# Scapy is not packaged in Alpine 3.20, so it is installed with pip (pinned).
FROM alpine:3.20
RUN apk add --no-cache nmap nmap-nping tcpdump iproute2 python3 py3-pip \
 && pip install --no-cache-dir --break-system-packages scapy==2.6.1
CMD ["sh"]
