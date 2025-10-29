#!/usr/bin/env bash
# Copyright (c) 2025 Alex Goodkind
# Author: Alex Goodkind (agoodkind)
# License: Apache-2.0

# Usage: ./deploy-example.sh [CONTAINER_ID] [HOSTNAME] [IP_ADDRESS]
# Defaults: CONTAINER_ID=300, HOSTNAME=elk-server, IP_ADDRESS=dhcp
CONTAINER_ID=${1:-300}
HOSTNAME=${2:-elk-server}
IP_ADDRESS=${3:-dhcp}

# Set IP config string
if [[ "$IP_ADDRESS" != "dhcp" ]]; then
	IP_CONFIG="ip=${IP_ADDRESS}/24,gw=192.168.1.1,ip6=dhcp"
else
	IP_CONFIG="ip=dhcp,ip6=dhcp"
fi

# Create and start container
pct create $CONTAINER_ID local:vztmpl/elk-stack-ubuntu-24.04.tar.zst --arch amd64 --cores 4 --hostname $HOSTNAME --memory 8192 --net0 name=eth0,bridge=vmbr0,$IP_CONFIG --onboot 1 --rootfs local-lvm:32 --features nesting=1
pct start $CONTAINER_ID && sleep 5
echo "Container deployed. ELK Stack is configured with default security settings."
echo "View credentials: pct exec $CONTAINER_ID -- cat /root/elk-credentials.txt"
