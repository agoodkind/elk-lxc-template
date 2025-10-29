#!/usr/bin/env bash
# Copyright (c) 2025 Alex Goodkind (alex@goodkind.io)
# License: Apache-2.0
#
# Build script for ELK Stack install wrapper
# Generates out/install/elk-stack-install.sh that sources scripts/install-elk.sh

set -e

# Output directories and file
OUT_DIR="out"
INSTALL_DIR="$OUT_DIR/install"
OUT_FILE="$INSTALL_DIR/elk-stack-install.sh"

# Create output directories
mkdir -p "$INSTALL_DIR"

# Configuration variables
REPO_URL="${REPO_URL:-https://raw.githubusercontent.com/agoodkind/elk-lxc-template}"
REPO_BRANCH="${REPO_BRANCH:-main}"
LOCAL_MODE="${LOCAL_MODE:-false}"

if [ "$LOCAL_MODE" = "true" ]; then
    echo "Generating $OUT_FILE (embedded mode)..."
    
    # Embed entire install-elk.sh
    {
        echo "#!/usr/bin/env bash"
        echo ""
        echo "# Copyright (c) 2025 Alex Goodkind"
        echo "# Author: Alex Goodkind (agoodkind)"
        echo "# License: Apache-2.0"
        echo "# Source: https://www.elastic.co/elk-stack"
        echo ""
        echo "# Embedded install-elk.sh for local testing"
        echo ""
        cat scripts/install-elk.sh | grep -v "^#!/usr/bin/env bash"
    } > "$OUT_FILE"
    
else
    echo "Generating $OUT_FILE (remote mode)..."
    
    # Thin wrapper that downloads install-elk.sh
    INSTALL_URL="$REPO_URL/$REPO_BRANCH/scripts/install-elk.sh"
    
    cat > "$OUT_FILE" << 'EOF'
#!/usr/bin/env bash

# Copyright (c) 2025 Alex Goodkind
# Author: Alex Goodkind (agoodkind)
# License: Apache-2.0
# Source: https://www.elastic.co/elk-stack

# Wrapper that downloads and executes install-elk.sh
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Download and execute main installation script
EOF
    echo "bash <(curl -fsSL $INSTALL_URL)" >> "$OUT_FILE"

fi

# Make executable
chmod +x "$OUT_FILE"

echo "✓ Generated $OUT_FILE successfully"
echo "  Mode: $([ "$LOCAL_MODE" = "true" ] && echo "Embedded" || echo "Remote wrapper")"
echo "  Source: $([ "$LOCAL_MODE" = "true" ] && echo "scripts/install-elk.sh (embedded)" || echo "$INSTALL_URL")"
