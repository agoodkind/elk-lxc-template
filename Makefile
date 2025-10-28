# Makefile for ELK Stack LXC Template
# Copyright (c) 2025 Alex Goodkind (alex@goodkind.io)
# License: Apache-2.0

.PHONY: all clean test test-quick check-components help

# Output directory
OUT_DIR = out

# Default target
all: $(OUT_DIR)/install.sh

help:
	@echo "ELK Stack LXC Template - Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  make               Generate Proxmox community script from components"
	@echo "  make clean         Remove generated files"
	@echo "  make test          Run comprehensive test suite"
	@echo "  make test-quick    Quick syntax validation"
	@echo "  make check-components  Verify all component files exist"
	@echo "  make help          Show this help message"
	@echo ""
	@echo "Generated file: out/install.sh (do not edit directly)"

# Create output directory
$(OUT_DIR):
	@mkdir -p $(OUT_DIR)

# Generate install.sh from component scripts
$(OUT_DIR)/install.sh: $(OUT_DIR) templates/install-header.sh scripts/install-elk.sh scripts/post-deploy.sh scripts/rotate-api-keys.sh templates/install-footer.sh config/elasticsearch.yml config/kibana.yml config/jvm.options.d/elasticsearch.options config/jvm.options.d/logstash.options config/logstash-pipelines/00-input.conf config/logstash-pipelines/30-output.conf
	@echo "Generating out/install.sh from component scripts..."
	@cat templates/install-header.sh > $(OUT_DIR)/install.sh
	@echo "" >> $(OUT_DIR)/install.sh
	@$(MAKE) -s embed-install-logic >> $(OUT_DIR)/install.sh
	@echo "" >> $(OUT_DIR)/install.sh
	@$(MAKE) -s embed-security-script >> $(OUT_DIR)/install.sh
	@echo "" >> $(OUT_DIR)/install.sh
	@$(MAKE) -s embed-rotation-script >> $(OUT_DIR)/install.sh
	@echo "" >> $(OUT_DIR)/install.sh
	@cat templates/install-footer.sh >> $(OUT_DIR)/install.sh
	@chmod +x $(OUT_DIR)/install.sh
	@echo "✓ Generated out/install.sh successfully"

# Embed install-elk.sh with config file embedding
embed-install-logic:
	@echo "# Define config file handler for Proxmox framework"
	@echo "handle_config() {"
	@echo "    local source=\"\$$1\""
	@echo "    local dest=\"\$$2\""
	@echo "    local mode=\"\$${3:-overwrite}\""
	@echo "    "
	@echo "    case \"\$$source\" in"
	@echo "        elasticsearch.yml)"
	@echo "            if [ \"\$$mode\" = \"append\" ]; then"
	@echo "                cat >> \"\$$dest\" << 'ELKEOF'"
	@cat config/elasticsearch.yml
	@echo "ELKEOF"
	@echo "            fi"
	@echo "            ;;"
	@echo "        elasticsearch.options)"
	@echo "            cat > \"\$$dest\" << 'ELKEOF'"
	@cat config/jvm.options.d/elasticsearch.options
	@echo "ELKEOF"
	@echo "            ;;"
	@echo "        00-input.conf)"
	@echo "            cat > \"\$$dest\" << 'ELKEOF'"
	@cat config/logstash-pipelines/00-input.conf
	@echo "ELKEOF"
	@echo "            ;;"
	@echo "        30-output.conf)"
	@echo "            cat > \"\$$dest\" << 'ELKEOF'"
	@cat config/logstash-pipelines/30-output.conf
	@echo "ELKEOF"
	@echo "            ;;"
	@echo "        logstash.options)"
	@echo "            cat > \"\$$dest\" << 'ELKEOF'"
	@cat config/jvm.options.d/logstash.options
	@echo "ELKEOF"
	@echo "            ;;"
	@echo "        kibana.yml)"
	@echo "            if [ \"\$$mode\" = \"append\" ]; then"
	@echo "                cat >> \"\$$dest\" << 'ELKEOF'"
	@cat config/kibana.yml
	@echo "ELKEOF"
	@echo "            fi"
	@echo "            ;;"
	@echo "    esac"
	@echo "}"
	@echo ""
	@echo "# Source install-elk.sh (contains all installation logic)"
	@cat scripts/install-elk.sh | grep -v "^#!/bin/bash" | grep -v "^# Copyright" | grep -v "^# Author" | grep -v "^# License" | tail -n +5

# Embed security configuration script
embed-security-script:
	@echo "msg_info \"Creating Management Scripts\""
	@echo "cat > /root/elk-configure-security.sh << 'EOFSCRIPT'"
	@cat scripts/post-deploy.sh | sed '1,/^set -e$$/d'
	@echo "EOFSCRIPT"
	@echo ""
	@echo "chmod +x /root/elk-configure-security.sh"
	@echo "msg_ok \"Created Security Configuration Script\""

# Embed API key rotation script
embed-rotation-script:
	@echo "msg_info \"Creating API Key Rotation Script\""
	@echo "cat > /root/elk-rotate-api-keys.sh << 'EOFSCRIPT'"
	@cat scripts/rotate-api-keys.sh | sed '1,/^set -e$$/d'
	@echo "EOFSCRIPT"
	@echo ""
	@echo "chmod +x /root/elk-rotate-api-keys.sh"
	@echo "msg_ok \"Created API Key Rotation Script\""

# Run comprehensive test suite
test:
	@bash tests/test-build.sh

# Quick syntax validation
test-quick: $(OUT_DIR)/install.sh
	@echo "Testing out/install.sh syntax..."
	@bash -n $(OUT_DIR)/install.sh && echo "✓ Syntax check passed"
	@echo "Checking for required functions..."
	@grep -q "function update_script" $(OUT_DIR)/install.sh && echo "✓ update_script function found"
	@grep -q "elk-configure-security.sh" $(OUT_DIR)/install.sh && echo "✓ Security script embedded"
	@grep -q "elk-rotate-api-keys.sh" $(OUT_DIR)/install.sh && echo "✓ Rotation script embedded"
	@echo "✓ All quick tests passed"

# Clean generated files
clean:
	@echo "Cleaning generated files..."
	@rm -rf $(OUT_DIR)
	@echo "✓ Cleaned"

# Validate component files exist
check-components:
	@echo "Checking component files..."
	@test -f templates/install-header.sh || (echo "✗ Missing templates/install-header.sh" && exit 1)
	@test -f templates/extract-install-logic.awk || (echo "✗ Missing templates/extract-install-logic.awk" && exit 1)
	@test -f templates/install-footer.sh || (echo "✗ Missing templates/install-footer.sh" && exit 1)
	@test -f scripts/install-steps.sh || (echo "✗ Missing scripts/install-steps.sh" && exit 1)
	@test -f scripts/install-elk.sh || (echo "✗ Missing scripts/install-elk.sh" && exit 1)
	@test -f scripts/post-deploy.sh || (echo "✗ Missing scripts/post-deploy.sh" && exit 1)
	@test -f scripts/rotate-api-keys.sh || (echo "✗ Missing scripts/rotate-api-keys.sh" && exit 1)
	@echo "✓ All components present"

