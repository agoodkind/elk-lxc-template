#!/usr/bin/env bash
# Copyright (c) 2025 Alex Goodkind (alex@goodkind.io)
# License: Apache-2.0
#
# Build script for ELK Stack CT wrapper
# 
# This script generates out/ct/elk-stack.sh, which is a complete Proxmox
# container creation script. It handles:
# 1. Container creation (CPU, RAM, disk, networking)
# 2. Installing ELK Stack inside the container
#
# FLOW:
#   installer.sh → out/install/elk-stack-install.sh (self-contained)
#   ct-wrapper.sh → out/ct/elk-stack.sh (calls build_container())
#
# Two modes:
#   - LOCAL_MODE=true:  Embeds everything (for local testing)
#   - LOCAL_MODE=false: ProxmoxVE submission mode (relies on ProxmoxVE infrastructure)

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================

# Output paths
OUT_DIR="out"
CT_DIR="$OUT_DIR/ct"
INSTALL_DIR="$OUT_DIR/install"
OUT_FILE="$CT_DIR/elk-stack.sh"
INSTALLER_FILE="$INSTALL_DIR/elk-stack-install.sh"

# Create output directory
mkdir -p "$CT_DIR"

# Configuration variables (passed from Makefile)
REPO_URL="${REPO_URL:-https://raw.githubusercontent.com/agoodkind/elk-lxc-template}"
REPO_BRANCH="${REPO_BRANCH:-main}"
PROXMOX_REPO_URL="${PROXMOX_REPO_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main}"
PROXMOX_LOCAL_PATH="${PROXMOX_LOCAL_PATH:-/root/ProxmoxVE}"
LOCAL_MODE="${LOCAL_MODE:-false}"

# ============================================================================
# STEP 1: Verify installer exists (Makefile handles building it)
# ============================================================================

if [ ! -f "$INSTALLER_FILE" ]; then
    echo "ERROR: Installer not found: $INSTALLER_FILE"
    echo "       Run 'make installer' first, or ensure installer target is built"
    exit 1
fi

echo "Using installer from: $INSTALLER_FILE"

# ============================================================================
# LOAD BUILD FUNCTIONS (sourced from lib/)
# ============================================================================

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the build mode implementations
source "$SCRIPT_DIR/lib/ct-local-mode.sh"
source "$SCRIPT_DIR/lib/ct-remote-mode.sh"

# ============================================================================
# STEP 2: Build CT wrapper based on mode
# ============================================================================

if [ "$LOCAL_MODE" = "true" ]; then
    build_local_mode
else
    build_remote_mode
fi

# ============================================================================
# STEP 3: Make executable and report success
# ============================================================================

chmod +x "$OUT_FILE"

echo ""
echo "✓ Generated $OUT_FILE successfully"
echo "  Mode: $([ "$LOCAL_MODE" = "true" ] && echo "Local/Embedded" || echo "ProxmoxVE submission")"
echo "  Framework: $([ "$LOCAL_MODE" = "true" ] && echo "Embedded build.func" || echo "$PROXMOX_REPO_URL/misc/build.func")"
echo "  Installer: $([ "$LOCAL_MODE" = "true" ] && echo "Embedded from $INSTALLER_FILE" || echo "ProxmoxVE serves from install/elk-stack-install.sh")"

