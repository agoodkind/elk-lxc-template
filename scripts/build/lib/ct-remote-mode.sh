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
    echo "  → build_container() automatically handles installer download"
    
    # Generate URLs for runtime downloads
    local build_func_source="source <(curl -fsSL $PROXMOX_REPO_URL/misc/build.func)"
    
    # Assemble the final CT wrapper script
    {
        # PART 1: Shebang and build.func source
        echo "#!/usr/bin/env bash"
        echo "$build_func_source"
        
        # PART 2: CT wrapper (variables, metadata, functions, build_container call)
        # Note: build_container() in build.func automatically downloads and executes
        # the installer from ProxmoxVE repo, so no manual installer call needed
        sed -n '/{{BUILD_FUNC_SOURCE}}/,/{{INSTALL_SCRIPT_OVERRIDE}}/p' \
            templates/elk-stack-ct-content.sh | sed '1d;$d'
        
        # PART 3: CT wrapper footer (success messages, final instructions)
        sed -n '/{{INSTALL_SCRIPT_OVERRIDE}}/,$p' templates/elk-stack-ct-content.sh | tail -n +2
    } > "$OUT_FILE"
}

