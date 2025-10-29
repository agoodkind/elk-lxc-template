#!/usr/bin/env bash
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

# Run install-elk.sh inside container
echo ""
echo "Starting ELK Stack installation in container $TEMPLATE_ID..."
echo "Installation will take 10-20 minutes (downloading large packages)"
echo ""
echo "Template build uses defaults: Full HTTPS, Elasticsearch 2GB, Logstash 1GB"
echo ""
echo "To monitor in another terminal:"
echo "  pct exec $TEMPLATE_ID -- tail -f /var/log/elk-install.log"
echo ""

# Set non-interactive mode for template build
# This bypasses interactive prompts and uses defaults
pct exec $TEMPLATE_ID -- bash -c "export SSL_CHOICE=1 CUSTOMIZE_MEMORY=n && /tmp/install-elk.sh" 2>&1 | \
	tee -a /var/log/proxmox-elk-build.log
INSTALL_EXIT=$?

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

# Cleanup container for template export
echo ""
echo "Running cleanup..."
pct exec $TEMPLATE_ID -- systemctl stop elasticsearch logstash kibana 2>/dev/null || true
pct exec $TEMPLATE_ID -- find /var/log -type f -exec truncate -s 0 {} \;
pct exec $TEMPLATE_ID -- rm -rf /tmp/* /var/tmp/*
pct exec $TEMPLATE_ID -- apt-get clean
pct exec $TEMPLATE_ID -- truncate -s 0 /etc/machine-id
pct exec $TEMPLATE_ID -- rm -f /var/lib/dbus/machine-id
pct exec $TEMPLATE_ID -- ln -s /etc/machine-id /var/lib/dbus/machine-id
pct exec $TEMPLATE_ID -- rm -f /etc/ssh/ssh_host_*
pct exec $TEMPLATE_ID -- bash -c "cat /dev/null > ~/.bash_history"
echo "✓ Cleanup completed"

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

TEMPLATE_CACHE_DIR="/var/lib/vz/template/cache"
TEMPLATE_SRC_FILE=$(ls -t $TEMPLATE_CACHE_DIR/vzdump-lxc-${TEMPLATE_ID}-*.tar.zst 2>/dev/null | head -1)
if [ -n "$TEMPLATE_SRC_FILE" ] && [ -f "$TEMPLATE_SRC_FILE" ]; then
	echo "Renaming template file... $(basename "$TEMPLATE_SRC_FILE") to elk-stack-ubuntu-24.04.tar.zst"
	mv "$TEMPLATE_SRC_FILE" "$TEMPLATE_CACHE_DIR/elk-stack-ubuntu-24.04.tar.zst"
else
	echo "ERROR: Template file not found after dump"
	exit 1
fi

# Output result
echo "Template ready: /var/lib/vz/template/cache/elk-stack-ubuntu-24.04.tar.zst"
