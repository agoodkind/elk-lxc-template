#!/usr/bin/env bash
# Copyright (c) 2025 Alex Goodkind (alex@goodkind.io)
# License: Apache-2.0
#
# Local mode build function for CT wrapper
# Creates fully embedded CT wrapper with everything self-contained
# Usage: For testing/development or offline installations

# ----------------------------------------------------------------------------
# Function: build_local_mode
# Description: Creates fully embedded CT wrapper with everything self-contained
# Requires: OUT_FILE, INSTALLER_FILE, PROXMOX_REPO_URL set by caller
# ----------------------------------------------------------------------------
build_local_mode() {
    echo "Building CT wrapper (LOCAL MODE - fully embedded)..."
    echo "  → Downloading build.func from: $PROXMOX_REPO_URL"
    echo "  → Embedding installer from: $INSTALLER_FILE"
    
    # Download build.func and strip out the install script download line
    # (we'll embed our own installer instead)
    local temp_build_func=$(mktemp)
    echo "  → Downloading and modifying build.func..."
    curl -fsSL "$PROXMOX_REPO_URL/misc/build.func" | \
        sed '/lxc-attach -n "\$CTID" -- bash -c "\$(curl -fsSL.*\/install\/\${var_install}\.sh)"/d' \
        > "$temp_build_func"
    
    # Assemble the final CT wrapper script
    {
        # PART 1: Shebang
        echo "#!/usr/bin/env bash"
        echo ""
        
        # PART 2: Embedded build.func (Proxmox framework functions)
        echo "# Embedded build.func (ProxmoxVE framework)"
        echo "# Provides: header_info, variables, color, catch_errors, etc."
        cat "$temp_build_func"
        echo ""
        
        # PART 3: CT wrapper header (variables, metadata, functions)
        echo "# ELK Stack container configuration"
        sed -n '/{{BUILD_FUNC_SOURCE}}/,/{{INSTALL_SCRIPT_OVERRIDE}}/p' \
            templates/elk-stack-ct-content.sh | sed '1d;$d'
        
        # PART 4: Embedded installer execution code
        echo ""
        echo "# Execute embedded installer (loaded from build-installer.sh)"
        echo "# The installer is fully embedded here for offline/local use"
        echo "# Note: pct push requires a file path (doesn't support stdin), so we create temp file"
        echo "HOST_SCRIPT=\"/tmp/elk-install-\$\$.sh\""
        echo "cat > \"\$HOST_SCRIPT\" << 'INSTALL_SCRIPT_EOF'"
        
        # Embed the pre-built installer (strip shebang)
        grep -v "^#!/usr/bin/env bash" "$INSTALLER_FILE"
        
        echo "INSTALL_SCRIPT_EOF"
        echo ""
        echo "# Push installer to container and make executable"
        echo 'chmod +x "$HOST_SCRIPT"'
        echo 'pct push "$CTID" "$HOST_SCRIPT" /tmp/install-elk.sh --perms 755'
        echo ''
        echo "# Execute installer in container with all environment variables"
        echo "# NON_INTERACTIVE=true is hardcoded at build time (dev-only, LOCAL_MODE=true)"
        cat <<'EOF'
lxc-attach -n "$CTID" -- bash -c "
  export VERBOSE='$VERBOSE'
  export DEBUG='$VERBOSE'
  export DIAGNOSTICS='$DIAGNOSTICS'
  export RANDOM_UUID='$RANDOM_UUID'
  export CACHER='$CACHER'
  export CACHER_IP='$CACHER_IP'
  export tz='$tz'
  export APPLICATION='$APPLICATION'
  export APP='$APP'
  export NSAPP='$NSAPP'
  export PASSWORD='$PASSWORD'
  export SSH_ROOT='$SSH_ROOT'
  export SSH_AUTHORIZED_KEY='$SSH_AUTHORIZED_KEY'
  export CTID='$CTID'
  export CTTYPE='$CTTYPE'
  export ENABLE_FUSE='$ENABLE_FUSE'
  export ENABLE_TUN='$ENABLE_TUN'
  export PCT_OSTYPE='$PCT_OSTYPE'
  export PCT_OSVERSION='$PCT_OSVERSION'
  export NON_INTERACTIVE='true'
  /tmp/install-elk.sh
"
EOF
        echo ""
        echo "# Cleanup: remove installer from container and host temp file"
        echo 'pct exec "$CTID" -- rm -f /tmp/install-elk.sh'
        echo 'rm -f "$HOST_SCRIPT"'
        echo ""
        
        # PART 5: CT wrapper footer (success messages, final instructions)
        sed -n '/{{INSTALL_SCRIPT_OVERRIDE}}/,$p' templates/elk-stack-ct-content.sh | tail -n +2
    } > "$OUT_FILE"
    
    rm -f "$temp_build_func"
}

