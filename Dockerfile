FROM docker.io/library/debian:12
RUN apt-get update && apt-get install iperf3 wireguard-tools iptables nftables iproute2 -y
