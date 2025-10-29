#!/usr/bin/env bash
# Copyright (c) 2025 Alex Goodkind (alex@goodkind.io)
# License: Apache-2.0
#
# Build script for ELK Stack CT wrapper
# Generates out/ct/elk-stack.sh with variable substitution

set -e

# Output directory and file
OUT_DIR="out"
CT_DIR="$OUT_DIR/ct"
OUT_FILE="$CT_DIR/elk-stack.sh"

# Create output directory
mkdir -p "$CT_DIR"

# Configuration variables (passed from Makefile)
REPO_URL="${REPO_URL:-https://raw.githubusercontent.com/agoodkind/elk-lxc-template}"
REPO_BRANCH="${REPO_BRANCH:-main}"
PROXMOX_REPO_URL="${PROXMOX_REPO_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main}"
PROXMOX_LOCAL_PATH="${PROXMOX_LOCAL_PATH:-/root/ProxmoxVE}"
LOCAL_MODE="${LOCAL_MODE:-false}"

if [ "$LOCAL_MODE" = "true" ]; then
    echo "Building local/hybrid mode CT wrapper..."
    echo "  ProxmoxVE path: $PROXMOX_LOCAL_PATH"
    echo "  Install script: $REPO_URL/$REPO_BRANCH/out/install/elk-stack-install.sh"
    
    # Use local build.func from filesystem
    BUILD_FUNC_REPLACEMENT="source ${PROXMOX_LOCAL_PATH}/misc/build.func"
    
    # Override install script download to point to our repo
    INSTALL_URL="$REPO_URL/$REPO_BRANCH/out/install/elk-stack-install.sh"
    INSTALL_SCRIPT_REPLACEMENT="lxc-attach -n \"\$CTID\" -- bash -c \"\$(curl -fsSL $INSTALL_URL)\""
    
else
    echo "Building remote mode CT wrapper..."
    echo "  ProxmoxVE URL: $PROXMOX_REPO_URL"
    echo "  Install script: $REPO_URL/$REPO_BRANCH/out/install/elk-stack-install.sh"
    
    # Download build.func from GitHub
    BUILD_FUNC_REPLACEMENT="source <(curl -fsSL $PROXMOX_REPO_URL/misc/build.func)"
    
    # Override install script download to point to our repo
    INSTALL_URL="$REPO_URL/$REPO_BRANCH/out/install/elk-stack-install.sh"
    INSTALL_SCRIPT_REPLACEMENT="lxc-attach -n \"\$CTID\" -- bash -c \"\$(curl -fsSL $INSTALL_URL)\""
fi

# Replace placeholders in template
sed -e "s|{{BUILD_FUNC_SOURCE}}|${BUILD_FUNC_REPLACEMENT}|g" \
    -e "s|{{INSTALL_SCRIPT_OVERRIDE}}|${INSTALL_SCRIPT_REPLACEMENT}|g" \
    templates/ct-wrapper.sh > "$OUT_FILE"

# Make executable
chmod +x "$OUT_FILE"

echo "✓ Generated $OUT_FILE successfully"
echo "  Mode: $([ "$LOCAL_MODE" = "true" ] && echo "Local/Hybrid" || echo "Remote")"
echo "  build.func: $([ "$LOCAL_MODE" = "true" ] && echo "$PROXMOX_LOCAL_PATH/misc/build.func" || echo "$PROXMOX_REPO_URL/misc/build.func")"
echo "  install script: $INSTALL_URL"

