#!/usr/bin/env bash
# Test suite for ELK LXC Template build system
# Copyright (c) 2025 Alex Goodkind (alex@goodkind.io)
# License: Apache-2.0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++))
    ((TESTS_RUN++))
}

test_fail() {
    echo -e "${RED}✗${NC} $1"
    ((TESTS_FAILED++))
    ((TESTS_RUN++))
}

test_header() {
    echo ""
    echo -e "${YELLOW}━━━ $1 ━━━${NC}"
}

cd "$(dirname "$0")/.."

test_header "Component File Validation"

if [[ -f templates/ct-wrapper.sh ]]; then test_pass "templates/ct-wrapper.sh exists"; else test_fail "templates/ct-wrapper.sh missing"; fi
if [[ -f templates/header-ascii.txt ]]; then test_pass "templates/header-ascii.txt exists"; else test_fail "templates/header-ascii.txt missing"; fi
if [[ -f templates/ui-metadata.json ]]; then test_pass "templates/ui-metadata.json exists"; else test_fail "templates/ui-metadata.json missing"; fi
if [[ -f scripts/install-elk.sh ]]; then test_pass "scripts/install-elk.sh exists"; else test_fail "scripts/install-elk.sh missing"; fi
if [[ -f scripts/build/build-ct-wrapper.sh ]]; then test_pass "build-ct-wrapper.sh exists"; else test_fail "build-ct-wrapper.sh missing"; fi
if [[ -f scripts/build/build-installer.sh ]]; then test_pass "build-installer.sh exists"; else test_fail "build-installer.sh missing"; fi
if [[ -f scripts/build/build-template.sh ]]; then test_pass "build-template.sh exists"; else test_fail "build-template.sh missing"; fi

test_header "Bash Syntax Validation"

for script in scripts/*.sh scripts/build/*.sh examples/*.sh; do
    if [[ -f "$script" ]]; then
        if bash -n "$script" 2>/dev/null; then
            test_pass "$(basename "$script") syntax valid"
        else
            test_fail "$(basename "$script") syntax error"
        fi
    fi
done

test_header "Installation Script Validation"

if grep -q "^step_start" scripts/install-elk.sh; then test_pass "install-elk.sh uses step_start"; else test_fail "install-elk.sh missing step_start"; fi
if grep -q "^step_done" scripts/install-elk.sh; then test_pass "install-elk.sh uses step_done"; else test_fail "install-elk.sh missing step_done"; fi

STEP_START_COUNT=$(grep -c "^step_start" scripts/install-elk.sh || echo 0)
STEP_DONE_COUNT=$(grep -c "^step_done" scripts/install-elk.sh || echo 0)
if [[ $STEP_START_COUNT -eq $STEP_DONE_COUNT && $STEP_START_COUNT -ge 19 ]]; then
    test_pass "step_start/step_done balanced ($STEP_START_COUNT steps)"
else
    test_fail "step_start/step_done mismatch (start: $STEP_START_COUNT, done: $STEP_DONE_COUNT)"
fi

if grep -q "if ! command -v msg_info" scripts/install-elk.sh; then test_pass "msg_info shim present"; else test_fail "msg_info shim missing"; fi
if grep -q "if ! command -v msg_ok" scripts/install-elk.sh; then test_pass "msg_ok shim present"; else test_fail "msg_ok shim missing"; fi
if grep -q "INTERACTIVE CONFIGURATION" scripts/install-elk.sh; then test_pass "Interactive configuration present"; else test_fail "Interactive configuration missing"; fi
if grep -q "SSL/TLS Configuration" scripts/install-elk.sh; then test_pass "SSL prompts present"; else test_fail "SSL prompts missing"; fi
if grep -q "Customize JVM heap" scripts/install-elk.sh; then test_pass "Memory prompts present"; else test_fail "Memory prompts missing"; fi

test_header "Build System Validation"

if make clean >/dev/null 2>&1; then test_pass "make clean works"; else test_fail "make clean failed"; fi
if make check-components >/dev/null 2>&1; then test_pass "make check-components works"; else test_fail "make check-components failed"; fi
if make installer >/dev/null 2>&1; then test_pass "make installer works"; else test_fail "make installer failed"; fi

test_header "Generated Files Validation"

if [[ -f out/ct/elk-stack.sh ]]; then test_pass "out/ct/elk-stack.sh generated"; else test_fail "out/ct/elk-stack.sh missing"; fi
if [[ -x out/ct/elk-stack.sh ]]; then test_pass "out/ct/elk-stack.sh executable"; else test_fail "out/ct/elk-stack.sh not executable"; fi
if bash -n out/ct/elk-stack.sh 2>/dev/null; then test_pass "out/ct/elk-stack.sh syntax valid"; else test_fail "out/ct/elk-stack.sh syntax error"; fi

if [[ -f out/install/elk-stack-install.sh ]]; then test_pass "out/install/elk-stack-install.sh generated"; else test_fail "out/install/elk-stack-install.sh missing"; fi
if bash -n out/install/elk-stack-install.sh 2>/dev/null; then test_pass "out/install/elk-stack-install.sh syntax valid"; else test_fail "out/install/elk-stack-install.sh syntax error"; fi

if [[ -f out/ct/headers/elk-stack ]]; then test_pass "ASCII header generated"; else test_fail "ASCII header missing"; fi
if [[ -f out/frontend/public/json/elk-stack.json ]]; then test_pass "JSON metadata generated"; else test_fail "JSON metadata missing"; fi

test_header "CT Wrapper Validation"

if grep -q "source <(curl.*build.func)" out/ct/elk-stack.sh; then test_pass "CT wrapper sources build.func"; else test_fail "build.func source missing"; fi
if grep -q "function update_script" out/ct/elk-stack.sh; then test_pass "update_script function present"; else test_fail "update_script missing"; fi
if grep -q "build_container" out/ct/elk-stack.sh; then test_pass "build_container call present"; else test_fail "build_container missing"; fi

test_header "Install Wrapper Validation"

if grep -q "bash <(curl.*install-elk.sh)" out/install/elk-stack-install.sh; then test_pass "Install wrapper downloads install-elk.sh"; else test_fail "install-elk.sh download missing"; fi

test_header "JSON Metadata Validation"

if grep -q '"name": "ELK-Stack"' out/frontend/public/json/elk-stack.json; then test_pass "JSON has correct name"; else test_fail "JSON name incorrect"; fi
if grep -q '"interface_port": 5601' out/frontend/public/json/elk-stack.json; then test_pass "JSON has correct port"; else test_fail "JSON port incorrect"; fi

test_header "Local Mode Build Test"

make clean >/dev/null 2>&1
if make installer-local >/dev/null 2>&1; then test_pass "make installer-local works"; else test_fail "make installer-local failed"; fi

CT_LINES=$(wc -l < out/ct/elk-stack.sh | tr -d ' ')
if [[ $CT_LINES -gt 1500 ]]; then test_pass "Local mode embeds build.func ($CT_LINES lines)"; else test_fail "Local mode too small ($CT_LINES lines)"; fi

test_header "Test Results"

echo ""
echo -e "Tests run: $TESTS_RUN"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
