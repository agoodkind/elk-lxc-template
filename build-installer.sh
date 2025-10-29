#!/usr/bin/env bash
# Copyright (c) 2025 Alex Goodkind (alex@goodkind.io)
# License: Apache-2.0
#
# Build script for ELK Stack Proxmox installer
# Generates install/elk-stack-install.sh from component files

set -e

# Output directories and file
OUT_DIR="out"
INSTALL_DIR="$OUT_DIR/install"
OUT_FILE="$INSTALL_DIR/elk-stack-install.sh"

# Create output directories
mkdir -p "$INSTALL_DIR"

echo "Generating $OUT_FILE from component scripts..."

# Start with header
cat templates/install-header.sh > "$OUT_FILE"
echo "" >> "$OUT_FILE"

# Embed handle_config function with inline config files
embed_handle_config() {
    cat << 'EOF'
# Define config file handler for Proxmox framework
handle_config() {
    local source="$1"
    local dest="$2"
    local mode="${3:-overwrite}"
    
    case "$source" in
        elasticsearch.yml)
            if [ "$mode" = "append" ]; then
                cat >> "$dest" << 'ELKEOF'
EOF

    cat config/elasticsearch.yml
    
    cat << 'EOF'
ELKEOF
            fi
            ;;
        elasticsearch.options)
            cat > "$dest" << 'ELKEOF'
EOF

    cat config/jvm.options.d/elasticsearch.options
    
    cat << 'EOF'
ELKEOF
            ;;
        00-input.conf)
            cat > "$dest" << 'ELKEOF'
EOF

    cat config/logstash-pipelines/00-input.conf
    
    cat << 'EOF'
ELKEOF
            ;;
        30-output.conf)
            cat > "$dest" << 'ELKEOF'
EOF

    cat config/logstash-pipelines/30-output.conf
    
    cat << 'EOF'
ELKEOF
            ;;
        logstash.options)
            cat > "$dest" << 'ELKEOF'
EOF

    cat config/jvm.options.d/logstash.options
    
    cat << 'EOF'
ELKEOF
            ;;
        kibana.yml)
            if [ "$mode" = "append" ]; then
                cat >> "$dest" << 'ELKEOF'
EOF

    cat config/kibana.yml
    
    cat << 'EOF'
ELKEOF
            fi
            ;;
    esac
}

# Source install-elk.sh (contains all installation logic)
EOF
}

embed_handle_config >> "$OUT_FILE"

# Strip headers from install-elk.sh and append
cat scripts/install-elk.sh \
    | grep -v "^#!/usr/bin/env bash" \
    | grep -v "^#!/bin/bash" \
    | grep -v "^# Copyright" \
    | grep -v "^# Author" \
    | grep -v "^# License" \
    | tail -n +5 >> "$OUT_FILE"

echo "" >> "$OUT_FILE"

# Note: Security configuration is now done interactively during installation
# post-deploy.sh is no longer embedded (kept for template build method only)

echo "" >> "$OUT_FILE"

# Embed API key rotation script
cat << 'EOF' >> "$OUT_FILE"
msg_info "Creating API Key Rotation Script"
cat > /root/elk-rotate-api-keys.sh << 'EOFSCRIPT'
EOF

# Strip headers from rotate-api-keys.sh
sed '1,/^set -e$/d' scripts/rotate-api-keys.sh >> "$OUT_FILE"

cat << 'EOF' >> "$OUT_FILE"
EOFSCRIPT

chmod +x /root/elk-rotate-api-keys.sh
msg_ok "Created API Key Rotation Script"
EOF

echo "" >> "$OUT_FILE"

# Append footer
cat templates/install-footer.sh >> "$OUT_FILE"

# Make executable
chmod +x "$OUT_FILE"

echo "✓ Generated $OUT_FILE successfully"

