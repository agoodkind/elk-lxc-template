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
    echo "  Downloading build.func from: $PROXMOX_REPO_URL"
    echo "  Install script: $REPO_URL/$REPO_BRANCH/out/install/elk-stack-install.sh"
    
    # Create temp file for modified build.func
    TEMP_BUILD_FUNC=$(mktemp)
    
    # Download build.func and remove the install script download line
    echo "  Downloading and modifying build.func..."
    curl -fsSL "$PROXMOX_REPO_URL/misc/build.func" | \
        sed '/lxc-attach -n "\$CTID" -- bash -c "\$(curl -fsSL.*\/install\/\${var_install}\.sh)"/d' \
        > "$TEMP_BUILD_FUNC"
    
    # Build output file in order (simpler than sed insertion)
    INSTALL_URL="$REPO_URL/$REPO_BRANCH/out/install/elk-stack-install.sh"
    
    {
        # 1. Shebang
        echo "#!/usr/bin/env bash"
        echo ""
        
        # 2. Embedded build.func
        echo "# Embedded build.func (modified for local testing)"
        cat "$TEMP_BUILD_FUNC"
        echo ""
        
        # 3. Rest of ct-wrapper (skip shebang and {{BUILD_FUNC_SOURCE}})
        sed -n '/{{BUILD_FUNC_SOURCE}}/,$ p' templates/ct-wrapper.sh | tail -n +2 \
            | sed "s|{{INSTALL_SCRIPT_OVERRIDE}}|lxc-attach -n \"\$CTID\" -- bash -c \"\$(curl -fsSL $INSTALL_URL)\"|g"
    } > "$OUT_FILE"
    
    rm -f "$TEMP_BUILD_FUNC"
else
    echo "Building remote mode CT wrapper..."
    echo "  ProxmoxVE URL: $PROXMOX_REPO_URL"
    echo "  Install script: $REPO_URL/$REPO_BRANCH/out/install/elk-stack-install.sh"
    
    # Download build.func from GitHub
    BUILD_FUNC_REPLACEMENT="source <(curl -fsSL $PROXMOX_REPO_URL/misc/build.func)"
    
    # Override install script download to point to our repo
    INSTALL_URL="$REPO_URL/$REPO_BRANCH/out/install/elk-stack-install.sh"
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

