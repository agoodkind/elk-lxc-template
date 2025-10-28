#!/bin/bash
# Copyright (c) 2025 Alex Goodkind
# Author: Alex Goodkind (agoodkind)
# License: Apache-2.0
#
# ELK Stack LXC Template Builder
# 
# ENTRYPOINT: Run this script on a Proxmox host to build the ELK
# template
# 
# This script:
# 1. Creates a new LXC container from Ubuntu 24.04 base image
# 2. Installs and configures the ELK stack inside the container
# 3. Cleans up the container to prepare it as a template
# 4. Exports it as a reusable LXC template
#
# Usage:
#   Run as root on Proxmox host:
#   ./build.sh
#
#   Use faster mirror (if default is slow):
#   UBUNTU_MIRROR=mirrors.mit.edu ./build.sh
#
#   Other fast mirrors:
#   - mirrors.mit.edu (MIT, US East Coast)
#   - mirror.math.princeton.edu (Princeton, US East Coast)
#   - mirror.us.leaseweb.net (LeaseWeb, Multiple US locations)
#
# Logs:
#   - Host output: stdout/stderr
#   - Container installation: /var/log/elk-install.log (inside container)
#   - Monitor live:
#     pct exec <ID> -- tail -f /var/log/elk-install.log

set -e

# Configurable variables
TEMPLATE_ID=900
TEMPLATE_NAME="elk-template"
BASE_IMAGE="ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
CORES=4
MEMORY=8192
SWAP=4096
DISK_SIZE=32
STORAGE="local-lvm"
TEMPLATE_STORAGE="local"

# Ubuntu mirror (set to faster mirror if default is slow)
# Options: archive.ubuntu.com (default), mirrors.mit.edu,
# mirror.math.princeton.edu, mirror.us.leaseweb.net
UBUNTU_MIRROR="${UBUNTU_MIRROR:-archive.ubuntu.com}"

# Auto-detect storage if defaults don't exist
echo "Checking storage configuration..."
if ! pvesm status | grep -q "^$STORAGE "; then
    echo "Warning: Storage '$STORAGE' not found, detecting alternatives..."
    # Try common storage names
	for storage_name in storage local-lvm local-zfs local-btrfs; do
		if pvesm status | grep -q "^$storage_name " && \
		   pvesm status | grep -q "^$storage_name .* active"; then
			STORAGE=$storage_name
			echo "✓ Using container storage: $STORAGE"
			break
		fi
	done
fi

if ! pvesm status | grep -q "^$STORAGE "; then
	echo "ERROR: No suitable storage found for containers"
	echo "Available storage:"
	pvesm status
	exit 1
fi

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
echo "Checking for base image: $BASE_IMAGE"
pveam update

if ! pveam list $TEMPLATE_STORAGE | grep -q "$BASE_IMAGE"; then
	echo "Template not found locally, attempting download..."
	# Try to download the template
	if ! pveam download $TEMPLATE_STORAGE $BASE_IMAGE; then
		echo ""
		echo "ERROR: Failed to download $BASE_IMAGE"
		echo ""
		echo "Available Ubuntu 24.04 templates:"
		pveam available | grep "ubuntu-24.04"
		echo ""
		echo "Already downloaded templates:"
		pveam list $TEMPLATE_STORAGE | grep ubuntu || \
			echo "  (none)"
		echo ""
		echo "To use a different template, edit BASE_IMAGE in build.sh"
		exit 1
	fi
else
	echo "✓ Template $BASE_IMAGE already downloaded"
fi

# Set vm.max_map_count for Elasticsearch
sysctl -w vm.max_map_count=262144
grep -q "vm.max_map_count" /etc/sysctl.conf || \
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf

# Create LXC container
pct create $TEMPLATE_ID \
	${TEMPLATE_STORAGE}:vztmpl/${BASE_IMAGE} \
	--arch amd64 \
	--cores $CORES \
	--hostname $TEMPLATE_NAME \
	--memory $MEMORY \
	--swap $SWAP \
	--net0 name=eth0,bridge=vmbr0,ip=dhcp,ip6=dhcp,\
type=veth \
	--onboot 0 \
	--ostype ubuntu \
	--rootfs ${STORAGE}:${DISK_SIZE} \
	--features nesting=1

# Start container and wait for boot
echo "Starting container $TEMPLATE_ID... and waiting for boot"
pct start $TEMPLATE_ID && sleep 5

echo ""
echo "Pushing scripts to container /tmp"
# Push scripts to container /tmp
for f in scripts/*.sh; do
	echo "  Pushing $f to /tmp/$(basename $f)..."
	pct push $TEMPLATE_ID "$f" "/tmp/$(basename $f)" \
		--perms 755
done

echo ""
echo "Pushing post-deploy and management scripts to /root"
# Push post-deploy and management scripts to /root
for f in scripts/post-deploy.sh scripts/rotate-api-keys.sh; do
	echo "  Pushing $f to /root/$(basename $f)..."
	pct push $TEMPLATE_ID "$f" "/root/$(basename $f)" \
		--perms 755
done

# Create config directory in container
echo ""
echo "Creating config directory in container /tmp/elk-config"
pct exec $TEMPLATE_ID -- mkdir -p /tmp/elk-config

# Push config files to container
for f in config/*.yml config/logstash-pipelines/*.conf \
		 config/jvm.options.d/*.options; do
	echo " Pushing $f to /tmp/elk-config/$(basename $f)..."
	pct push $TEMPLATE_ID "$f" "/tmp/elk-config/$(basename $f)"
done

# Run install-elk.sh inside container
echo ""
echo "Starting ELK Stack installation in container $TEMPLATE_ID..."
echo "Installation will take 10-20 minutes (downloading large packages)"
echo ""
echo "To monitor in another terminal:"
echo "  pct exec $TEMPLATE_ID -- tail -f /var/log/elk-install.log"
echo ""

# install-elk.sh already has built-in shims and logging
# Use pipefail to catch exit codes through pipes
set -o pipefail
pct exec $TEMPLATE_ID -- /tmp/install-elk.sh 2>&1 | \
	tee -a /var/log/proxmox-elk-build.log
INSTALL_EXIT=$?
set +o pipefail

if [ $INSTALL_EXIT -eq 0 ]; then
	echo ""
	echo "============================================"
	echo "✓ Installation completed successfully"
else
	echo ""
	echo "============================================"
	echo "✗ Installation failed with exit code $INSTALL_EXIT"
	echo "Check log: pct exec $TEMPLATE_ID -- cat \
		/var/log/elk-install.log"
	exit 1
fi

# Run cleanup script
echo ""
echo "Running cleanup..."
pct exec $TEMPLATE_ID -- /tmp/cleanup.sh

# Stop container
echo "Stopping container $TEMPLATE_ID..."
pct stop $TEMPLATE_ID

# Dump container to template
echo "Dumping container $TEMPLATE_ID to template..."
vzdump $TEMPLATE_ID --compress zstd --dumpdir /var/lib/vz/template/cache --mode stop

if [ -f /var/lib/vz/template/cache/elk-stack-ubuntu-24.04.tar.zst ]; then
	echo "Old template file found..."
	echo "Removing old template file... \
		/var/lib/vz/template/cache/elk-stack-ubuntu-24.04.tar.zst"
	rm -f /var/lib/vz/template/cache/elk-stack-ubuntu-24.04.tar.zst
fi

# Rename template file

if [ -f "$(ls -t vzdump-lxc-${TEMPLATE_ID}-*.tar.zst | head -1)" ]; then
	echo "Renaming template file... \
		$(ls -t vzdump-lxc-${TEMPLATE_ID}-*.tar.zst | head -1) \
		to elk-stack-ubuntu-24.04.tar.zst"
	cd /var/lib/vz/template/cache && \
		mv "$(ls -t vzdump-lxc-${TEMPLATE_ID}-*.tar.zst 2>/dev/null | head -1)" \
		elk-stack-ubuntu-24.04.tar.zst
fi

# Output result
echo "Template ready: /var/lib/vz/template/cache/elk-stack-ubuntu-24.04.tar.zst"
