# Makefile for ELK Stack LXC Template
# Copyright (c) 2025 Alex Goodkind (alex@goodkind.io)
# License: Apache-2.0

.PHONY: clean test test-quick check-components help

# Output directories
OUT_DIR = out
CT_DIR = $(OUT_DIR)/ct
INSTALL_DIR = $(OUT_DIR)/install
HEADER_DIR = $(CT_DIR)/headers
JSON_DIR = $(OUT_DIR)/frontend/public/json

# Help is the interactive default
.DEFAULT_GOAL := help

# Template build target (runs build-template.sh)
.PHONY: template
template:
	bash build-template.sh

# Install target (generates all submission files)
.PHONY: installer
installer: $(CT_DIR)/elk-stack.sh $(INSTALL_DIR)/elk-stack-install.sh $(HEADER_DIR)/elk-stack $(JSON_DIR)/elk-stack.json

# Default help target
help:
	@echo "ELK Stack LXC Template - Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  make template        Build template (runs build-template.sh)"
	@echo "  make installer       Build install script (out/install.sh)"
	@echo "  make clean           Remove generated files"
	@echo "  make test            Run comprehensive test suite"
	@echo "  make test-quick      Quick syntax validation"
	@echo "  make check-components  Verify all component files exist"
	@echo "  make help            Show this help message"

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
	@cp templates/ct-wrapper.sh $(CT_DIR)/elk-stack.sh
	@chmod +x $(CT_DIR)/elk-stack.sh
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

