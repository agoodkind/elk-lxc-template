#!/usr/bin/env bash
# Copyright (c) 2025 Alex Goodkind (alex@goodkind.io)
# License: Apache-2.0
#
# Remote mode build function for CT wrapper
# Creates thin CT wrapper that downloads from GitHub at runtime
# Usage: For production/submission to ProxmoxVE community scripts

# ----------------------------------------------------------------------------
# Function: build_remote_mode
# Description: Creates thin CT wrapper that downloads from GitHub at runtime
# Requires: OUT_FILE, REPO_URL, REPO_BRANCH, PROXMOX_REPO_URL set by caller
# ----------------------------------------------------------------------------
build_remote_mode() {
    echo "Building CT wrapper (REMOTE MODE - downloads from GitHub)..."
    echo "  → ProxmoxVE framework: $PROXMOX_REPO_URL"
    echo "  → Installer URL: $REPO_URL/$REPO_BRANCH/scripts/install/elk-stack.sh"
    
    # Generate URLs for runtime downloads
    local build_func_source="source <(curl -fsSL $PROXMOX_REPO_URL/misc/build.func)"
    local install_url="$REPO_URL/$REPO_BRANCH/scripts/install/elk-stack.sh"
    
    # Build install command with environment variable exports
    local install_command="lxc-attach -n \"\$CTID\" -- bash -c \"
  export VERBOSE='\$VERBOSE'
  export STD='\$STD'
  export DEBUG='\$DEBUG'
  export DIAGNOSTICS='yes'
  export RANDOM_UUID='\$RANDOM_UUID'
  export CACHER='\$CACHER'
  export CACHER_IP='\$CACHER_IP'
  export tz='\$tz'
  export APPLICATION='\$APPLICATION'
  export APP='\$APP'
  export NSAPP='\$NSAPP'
  export PASSWORD='\$PASSWORD'
  export SSH_ROOT='\$SSH_ROOT'
  export SSH_AUTHORIZED_KEY='\$SSH_AUTHORIZED_KEY'
  export CTID='\$CTID'
  export CTTYPE='\$CTTYPE'
  export ENABLE_FUSE='\$ENABLE_FUSE'
  export ENABLE_TUN='\$ENABLE_TUN'
  export PCT_OSTYPE='\$PCT_OSTYPE'
  export PCT_OSVERSION='\$PCT_OSVERSION'
  export IP='\$IP'
  \\\$(curl -fsSL $install_url)
\""
    
    # Replace placeholders in template with URLs
    sed -e "s|{{BUILD_FUNC_SOURCE}}|${build_func_source}|g" \
        -e "s|{{INSTALL_SCRIPT_OVERRIDE}}|${install_command}|g" \
        templates/elk-stack-ct-content.sh > "$OUT_FILE"
}

