# Makefile for ELK Stack LXC Template
# Copyright (c) 2025 Alex Goodkind (alex@goodkind.io)
# License: Apache-2.0

.PHONY: clean test test-quick check-components help

# Output directory
OUT_DIR = out


# Help is the interactive default
.DEFAULT_GOAL := help

# Template build target (runs build-template.sh)
.PHONY: template
template:
	bash build-template.sh

# Install target (runs scripts/install-elk.sh)
.PHONY: installer
installer: $(OUT_DIR)/install.sh

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

# Create output directory
$(OUT_DIR):
	@mkdir -p $(OUT_DIR)

# Generate install.sh from component scripts
$(OUT_DIR)/install.sh: $(OUT_DIR) templates/install-header.sh scripts/install-elk.sh scripts/post-deploy.sh scripts/rotate-api-keys.sh templates/install-footer.sh config/elasticsearch.yml config/kibana.yml config/jvm.options.d/elasticsearch.options config/jvm.options.d/logstash.options config/logstash-pipelines/00-input.conf config/logstash-pipelines/30-output.conf build-installer.sh
	@bash build-installer.sh

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
	@test -f templates/install-footer.sh || (echo "✗ Missing templates/install-footer.sh" && exit 1)
	@test -f scripts/install-elk.sh || (echo "✗ Missing scripts/install-elk.sh" && exit 1)
	@test -f scripts/post-deploy.sh || (echo "✗ Missing scripts/post-deploy.sh" && exit 1)
	@test -f scripts/rotate-api-keys.sh || (echo "✗ Missing scripts/rotate-api-keys.sh" && exit 1)
	@echo "✓ All components present"

