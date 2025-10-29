# Makefile for ELK Stack LXC Template
# Copyright (c) 2025 Alex Goodkind (alex@goodkind.io)
# License: Apache-2.0

.PHONY: clean test test-quick check-components help installer-local

# Output directories
OUT_DIR = out
CT_DIR = $(OUT_DIR)/ct
INSTALL_DIR = $(OUT_DIR)/install
HEADER_DIR = $(CT_DIR)/headers
JSON_DIR = $(OUT_DIR)/frontend/public/json

# Build configuration variables
REPO_URL ?= https://raw.githubusercontent.com/agoodkind/elk-lxc-template
REPO_BRANCH ?= main
PROXMOX_REPO_URL ?= https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main
PROXMOX_LOCAL_PATH ?= /root/ProxmoxVE

# Help is the interactive default
.DEFAULT_GOAL := help

# Template build target (runs build-template.sh)
.PHONY: template
template:
	bash build-template.sh

# Install target (generates all submission files)
.PHONY: installer
installer: $(CT_DIR)/elk-stack.sh $(INSTALL_DIR)/elk-stack-install.sh $(HEADER_DIR)/elk-stack $(JSON_DIR)/elk-stack.json

# Local mode installer (uses local ProxmoxVE folder)
installer-local: export LOCAL_MODE=true
installer-local: $(CT_DIR)/elk-stack.sh $(INSTALL_DIR)/elk-stack-install.sh $(HEADER_DIR)/elk-stack $(JSON_DIR)/elk-stack.json

# Default help target
help:
	@echo "ELK Stack LXC Template - Makefile"
	@echo ""
	@echo "Build Targets:"
	@echo "  make installer              Build for ProxmoxVE submission (remote mode)"
	@echo "  make installer-local        Build for local testing (hybrid mode)"
	@echo "  make template               Build LXC template (runs build-template.sh)"
	@echo ""
	@echo "Test Targets:"
	@echo "  make test                   Run comprehensive test suite"
	@echo "  make test-quick             Quick syntax validation"
	@echo "  make check-components       Verify all component files exist"
	@echo ""
	@echo "Build Configuration:"
	@echo "  REPO_URL=<url>              Your GitHub repo URL (default: agoodkind/elk-lxc-template)"
	@echo "  REPO_BRANCH=<branch>        Branch to use (default: main)"
	@echo "  PROXMOX_REPO_URL=<url>      ProxmoxVE repo URL (default: community-scripts/ProxmoxVE)"
	@echo "  PROXMOX_LOCAL_PATH=<path>   Local ProxmoxVE path (default: /root/ProxmoxVE)"
	@echo ""
	@echo "Examples:"
	@echo "  make installer                                    # Production build"
	@echo "  make installer REPO_BRANCH=dev                    # Test dev branch"
	@echo "  make installer-local PROXMOX_LOCAL_PATH=/custom   # Local testing"
	@echo ""
	@echo "Runtime Configuration (during installation):"
	@echo "  - SSL/TLS options (Full HTTPS/Backend only/No SSL)"
	@echo "  - JVM heap sizes (optional customization)"
	@echo "  - Verbose output (controlled by Proxmox framework)"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean                  Remove generated files"

# Create output directories
$(OUT_DIR):
	@mkdir -p $(OUT_DIR)
	@mkdir -p $(CT_DIR)
	@mkdir -p $(INSTALL_DIR)
	@mkdir -p $(HEADER_DIR)
	@mkdir -p $(JSON_DIR)

# Generate ct/elk-stack.sh (wrapper script)
$(CT_DIR)/elk-stack.sh: $(OUT_DIR) templates/ct-wrapper.sh
	@echo "Generating $(CT_DIR)/elk-stack.sh..."
	@REPO_URL=$(REPO_URL) \
	 REPO_BRANCH=$(REPO_BRANCH) \
	 PROXMOX_REPO_URL=$(PROXMOX_REPO_URL) \
	 PROXMOX_LOCAL_PATH=$(PROXMOX_LOCAL_PATH) \
	 LOCAL_MODE=$(LOCAL_MODE) \
	 bash build-ct-wrapper.sh
	@echo "✓ Generated $(CT_DIR)/elk-stack.sh successfully"

# Generate install/elk-stack-install.sh (installation logic)
$(INSTALL_DIR)/elk-stack-install.sh: $(OUT_DIR) templates/install-header.sh scripts/install-elk.sh scripts/rotate-api-keys.sh templates/install-footer.sh config/elasticsearch.yml config/kibana.yml config/jvm.options.d/elasticsearch.options config/jvm.options.d/logstash.options config/logstash-pipelines/00-input.conf config/logstash-pipelines/30-output.conf build-installer.sh
	@bash build-installer.sh

# Generate ct/headers/elk-stack (ASCII art header)
$(HEADER_DIR)/elk-stack: $(OUT_DIR) templates/header-ascii.txt
	@echo "Generating $(HEADER_DIR)/elk-stack..."
	@cp templates/header-ascii.txt $(HEADER_DIR)/elk-stack
	@echo "✓ Generated $(HEADER_DIR)/elk-stack successfully"

# Generate frontend/public/json/elk-stack.json (UI metadata)
$(JSON_DIR)/elk-stack.json: $(OUT_DIR) templates/ui-metadata.json
	@echo "Generating $(JSON_DIR)/elk-stack.json..."
	@cp templates/ui-metadata.json $(JSON_DIR)/elk-stack.json
	@echo "✓ Generated $(JSON_DIR)/elk-stack.json successfully"

# Run comprehensive test suite
test:
	@bash tests/test-build.sh

# Quick syntax validation
test-quick: $(CT_DIR)/elk-stack.sh $(INSTALL_DIR)/elk-stack-install.sh
	@echo "Testing ct/elk-stack.sh syntax..."
	@bash -n $(CT_DIR)/elk-stack.sh && echo "✓ CT wrapper syntax check passed"
	@echo "Checking for required functions in ct wrapper..."
	@grep -q "function update_script" $(CT_DIR)/elk-stack.sh && echo "✓ update_script function found"
	@grep -q "build_container" $(CT_DIR)/elk-stack.sh && echo "✓ build_container call found"
	@echo ""
	@echo "Testing install/elk-stack-install.sh syntax..."
	@bash -n $(INSTALL_DIR)/elk-stack-install.sh && echo "✓ Install script syntax check passed"
	@echo "Checking for embedded scripts..."
	@grep -q "elk-rotate-api-keys.sh" $(INSTALL_DIR)/elk-stack-install.sh && echo "✓ Rotation script embedded"
	@grep -q "INTERACTIVE CONFIGURATION" $(INSTALL_DIR)/elk-stack-install.sh && echo "✓ Interactive configuration found"
	@echo "✓ All quick tests passed"

# Clean generated files
clean:
	@echo "Cleaning generated files..."
	@rm -rf $(OUT_DIR)
	@echo "✓ Cleaned"

# Validate component files exist
check-components:
	@echo "Checking component files..."
	@test -f templates/ct-wrapper.sh || (echo "✗ Missing templates/ct-wrapper.sh" && exit 1)
	@test -f templates/install-header.sh || (echo "✗ Missing templates/install-header.sh" && exit 1)
	@test -f templates/install-footer.sh || (echo "✗ Missing templates/install-footer.sh" && exit 1)
	@test -f scripts/install-elk.sh || (echo "✗ Missing scripts/install-elk.sh" && exit 1)
	@test -f scripts/rotate-api-keys.sh || (echo "✗ Missing scripts/rotate-api-keys.sh" && exit 1)
	@echo "✓ All components present"

