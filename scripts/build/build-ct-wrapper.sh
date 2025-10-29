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
    echo "Building local mode CT wrapper (fully embedded)..."
    echo "  Downloading build.func from: $PROXMOX_REPO_URL"
    echo "  Embedding install script from: scripts/install-elk.sh"
    
    # Create temp file for modified build.func
    TEMP_BUILD_FUNC=$(mktemp)
    
    # Download build.func and remove the install script download line
    echo "  Downloading and modifying build.func..."
    curl -fsSL "$PROXMOX_REPO_URL/misc/build.func" | \
        sed '/lxc-attach -n "\$CTID" -- bash -c "\$(curl -fsSL.*\/install\/\${var_install}\.sh)"/d' \
        > "$TEMP_BUILD_FUNC"
    
    # Build file directly without sed substitution
    {
        # 1. Shebang
        echo "#!/usr/bin/env bash"
        echo ""
        
        # 2. Embedded build.func
        echo "# Embedded build.func (modified for local testing)"
        cat "$TEMP_BUILD_FUNC"
        echo ""
        
        # 3. CT wrapper content (between {{BUILD_FUNC_SOURCE}} and {{INSTALL_SCRIPT_OVERRIDE}})
        sed -n '/{{BUILD_FUNC_SOURCE}}/,/{{INSTALL_SCRIPT_OVERRIDE}}/p' templates/ct-wrapper.sh \
            | sed '1d;$d'
        
        # 4. Embedded install script (write to host temp, push to container, execute)
        echo ""
        echo "# Execute embedded install script (local testing mode)"
        echo "HOST_SCRIPT=\"/tmp/elk-install-\$\$.sh\""
        echo "cat > \"\$HOST_SCRIPT\" << 'INSTALL_SCRIPT_EOF'"
        cat scripts/install-elk.sh
        echo "INSTALL_SCRIPT_EOF"
        echo ""
        echo 'chmod +x "$HOST_SCRIPT"'
        echo 'pct push "$CTID" "$HOST_SCRIPT" /tmp/install-elk.sh --perms 755'
        echo ''
        echo '# Pass all exported environment variables to container'
        cat <<'EOF'
lxc-attach -n "$CTID" -- bash -c "
  export VERBOSE='$VERBOSE'
  export DIAGNOSTICS='$DIAGNOSTICS'
  export RANDOM_UUID='$RANDOM_UUID'
  export CACHER='$CACHER'
  export CACHER_IP='$CACHER_IP'
  export tz='$tz'
  export APPLICATION='$APPLICATION'
  export app='$app'
  export PASSWORD='$PASSWORD'
  export SSH_ROOT='$SSH_ROOT'
  export SSH_AUTHORIZED_KEY='$SSH_AUTHORIZED_KEY'
  export CTID='$CTID'
  export CTTYPE='$CTTYPE'
  export ENABLE_FUSE='$ENABLE_FUSE'
  export ENABLE_TUN='$ENABLE_TUN'
  export PCT_OSTYPE='$PCT_OSTYPE'
  export PCT_OSVERSION='$PCT_OSVERSION'
  /tmp/install-elk.sh
"
EOF
        echo 'pct exec "$CTID" -- rm -f /tmp/install-elk.sh'
        echo 'rm -f "$HOST_SCRIPT"'
        echo ""
        
        # 5. Rest of ct-wrapper (after {{INSTALL_SCRIPT_OVERRIDE}})
        sed -n '/{{INSTALL_SCRIPT_OVERRIDE}}/,$p' templates/ct-wrapper.sh | tail -n +2
    } > "$OUT_FILE"
    
    rm -f "$TEMP_BUILD_FUNC"
else
    echo "Building remote mode CT wrapper..."
    echo "  ProxmoxVE URL: $PROXMOX_REPO_URL"
    echo "  Install script: $REPO_URL/$REPO_BRANCH/scripts/install-elk.sh"
    
    # Download build.func from GitHub
    BUILD_FUNC_REPLACEMENT="source <(curl -fsSL $PROXMOX_REPO_URL/misc/build.func)"
    
    # Download raw install-elk.sh from our repo
    INSTALL_URL="$REPO_URL/$REPO_BRANCH/scripts/install-elk.sh"
    INSTALL_SCRIPT_REPLACEMENT="lxc-attach -n \"\$CTID\" -- bash -c \"\$(curl -fsSL $INSTALL_URL)\""
    
    # Replace placeholders in template
    sed -e "s|{{BUILD_FUNC_SOURCE}}|${BUILD_FUNC_REPLACEMENT}|g" \
        -e "s|{{INSTALL_SCRIPT_OVERRIDE}}|${INSTALL_SCRIPT_REPLACEMENT}|g" \
        templates/ct-wrapper.sh > "$OUT_FILE"
fi

# Make executable
chmod +x "$OUT_FILE"

echo "✓ Generated $OUT_FILE successfully"
echo "  Mode: $([ "$LOCAL_MODE" = "true" ] && echo "Local/Hybrid" || echo "Remote")"
echo "  build.func: $([ "$LOCAL_MODE" = "true" ] && echo "$PROXMOX_LOCAL_PATH/misc/build.func" || echo "$PROXMOX_REPO_URL/misc/build.func")"
echo "  install script: $INSTALL_URL"

