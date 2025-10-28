#!/bin/bash
# Copyright (c) 2025 Alex Goodkind
# Author: Alex Goodkind (agoodkind)
# License: Apache-2.0
# This script builds an LXC template for the ELK stack on Ubuntu 24.04
# It creates a container, installs and configures the ELK stack,
# cleans up the container, and then exports it as a reusable template.

set -e

# Configurable variables
TEMPLATE_ID=900
TEMPLATE_NAME="elk-template"
BASE_IMAGE="ubuntu-24.04-standard_24.04-1_amd64.tar.zst"
CORES=4
MEMORY=8192
SWAP=4096
DISK_SIZE=32
STORAGE="local-lvm"
TEMPLATE_STORAGE="local"

# Require root
if [[ $EUID -ne 0 ]]; then
	echo "Run as root"
	exit 1
fi

# Destroy existing container if present
if pct status $TEMPLATE_ID &>/dev/null; then
	read -p "Destroy $TEMPLATE_ID? (y/N): " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		pct stop $TEMPLATE_ID 2>/dev/null || true
		pct destroy $TEMPLATE_ID
	else
		exit 1
	fi
fi

# Download base image if not present
pveam update
if ! pveam list $TEMPLATE_STORAGE | grep -q "$BASE_IMAGE"; then
	pveam download $TEMPLATE_STORAGE $BASE_IMAGE
fi

# Set vm.max_map_count for Elasticsearch
sysctl -w vm.max_map_count=262144
grep -q "vm.max_map_count" /etc/sysctl.conf || echo "vm.max_map_count=262144" >> /etc/sysctl.conf

# Create LXC container
pct create $TEMPLATE_ID \
	${TEMPLATE_STORAGE}:vztmpl/${BASE_IMAGE} \
	--arch amd64 \
	--cores $CORES \
	--hostname $TEMPLATE_NAME \
	--memory $MEMORY \
	--swap $SWAP \
	--net0 name=eth0,bridge=vmbr0,ip=dhcp,ip6=dhcp,type=veth \
	--onboot 0 \
	--ostype ubuntu \
	--rootfs ${STORAGE}:${DISK_SIZE} \
	--features nesting=1

# Start container and wait for boot
pct start $TEMPLATE_ID && sleep 5

# Push scripts to container /tmp
for f in scripts/*.sh; do
	pct push $TEMPLATE_ID "$f" "/tmp/$(basename $f)" --perms 755
done

# Push post-deploy and management scripts to /root
pct push $TEMPLATE_ID scripts/post-deploy.sh /root/post-deploy.sh --perms 755
pct push $TEMPLATE_ID scripts/rotate-api-keys.sh /root/rotate-api-keys.sh --perms 755

# Create config directory in container
pct exec $TEMPLATE_ID -- mkdir -p /tmp/elk-config

# Push config files to container
for f in config/*.yml config/logstash-pipelines/*.conf config/jvm.options.d/*.options; do
	pct push $TEMPLATE_ID "$f" "/tmp/elk-config/$(basename $f)"
done

# Run install and cleanup scripts inside container
pct exec $TEMPLATE_ID -- /tmp/install-elk.sh && pct exec $TEMPLATE_ID -- /tmp/cleanup.sh

# Stop container
pct stop $TEMPLATE_ID

# Dump container to template
vzdump $TEMPLATE_ID --compress zstd --dumpdir /var/lib/vz/template/cache --mode stop

# Rename template file
cd /var/lib/vz/template/cache && mv "$(ls -t vzdump-lxc-${TEMPLATE_ID}-*.tar.zst | head -1)" elk-stack-ubuntu-24.04.tar.zst

# Output result
echo "Template ready: /var/lib/vz/template/cache/elk-stack-ubuntu-24.04.tar.zst"
