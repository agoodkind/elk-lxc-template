#!/usr/bin/env bash
# Test suite for ELK LXC Template build system
# Copyright (c) 2025 Alex Goodkind (alex@goodkind.io)
# License: Apache-2.0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
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

# Change to project root
cd "$(dirname "$0")/.."

test_header "Component File Validation"

# Test: Component files exist
if [[ -f templates/install-header.sh ]]; then
    test_pass "templates/install-header.sh exists"
else
    test_fail "templates/install-header.sh missing"
fi

if [[ -f templates/install-footer.sh ]]; then
    test_pass "templates/install-footer.sh exists"
else
    test_fail "templates/install-footer.sh missing"
fi

if [[ -f scripts/install-elk.sh ]]; then
    test_pass "scripts/install-elk.sh exists"
else
    test_fail "scripts/install-elk.sh missing"
fi

if [[ -f scripts/post-deploy.sh ]]; then
    test_pass "scripts/post-deploy.sh exists"
else
    test_fail "scripts/post-deploy.sh missing"
fi

if [[ -f scripts/rotate-api-keys.sh ]]; then
    test_pass "scripts/rotate-api-keys.sh exists"
else
    test_fail "scripts/rotate-api-keys.sh missing"
fi

test_header "Bash Syntax Validation"

# Test: Bash syntax for all shell scripts
for script in templates/install-header.sh templates/install-footer.sh scripts/*.sh examples/*.sh; do
    if [[ -f "$script" ]]; then
        if bash -n "$script" 2>/dev/null; then
            test_pass "$(basename "$script") syntax valid"
        else
            test_fail "$(basename "$script") syntax error"
        fi
    fi
done

test_header "Installation Script Validation"

# Test: install-elk.sh has proper structure
if grep -q "^step_start" scripts/install-elk.sh; then
    test_pass "install-elk.sh uses step_start function"
else
    test_fail "install-elk.sh missing step_start function"
fi

if grep -q "^step_done" scripts/install-elk.sh; then
    test_pass "install-elk.sh uses step_done function"
else
    test_fail "install-elk.sh missing step_done function"
fi

# Test: Verify step_start and step_done are balanced
STEP_START_COUNT=$(grep -c "^step_start" scripts/install-elk.sh || echo 0)
STEP_DONE_COUNT=$(grep -c "^step_done" scripts/install-elk.sh || echo 0)

if [[ $STEP_START_COUNT -eq $STEP_DONE_COUNT && $STEP_START_COUNT -gt 0 ]]; then
    test_pass "step_start/step_done balanced ($STEP_START_COUNT steps)"
else
    test_fail "step_start/step_done mismatch (start: $STEP_START_COUNT, done: $STEP_DONE_COUNT)"
fi

# Test: Install script has shim functions
if grep -q "if ! command -v msg_info" scripts/install-elk.sh; then
    test_pass "install-elk.sh has msg_info shim"
else
    test_fail "install-elk.sh missing msg_info shim"
fi

if grep -q "if ! command -v msg_ok" scripts/install-elk.sh; then
    test_pass "install-elk.sh has msg_ok shim"
else
    test_fail "install-elk.sh missing msg_ok shim"
fi

if grep -q "if ! command -v handle_config" scripts/install-elk.sh; then
    test_pass "install-elk.sh has handle_config shim"
else
    test_fail "install-elk.sh missing handle_config shim"
fi

test_header "Makefile Target Validation"

# Test: Make clean works
if make clean >/dev/null 2>&1; then
    test_pass "make clean executes successfully"
else
    test_fail "make clean failed"
fi

# Test: Make check-components works
if make check-components >/dev/null 2>&1; then
    test_pass "make check-components validates all files"
else
    test_fail "make check-components failed"
fi

# Test: Make installer generates output
if make installer >/dev/null 2>&1; then
    test_pass "make installer generates install.sh"
else
    test_fail "make installer failed"
fi

test_header "Generated Script Validation"

# Test: Generated script exists
if [[ -f out/install.sh ]]; then
    test_pass "out/install.sh generated"
else
    test_fail "out/install.sh not generated"
    echo ""
    echo -e "${RED}Cannot continue without generated script${NC}"
    exit 1
fi

# Test: Generated script is executable
if [[ -x out/install.sh ]]; then
    test_pass "out/install.sh is executable"
else
    test_fail "out/install.sh is not executable"
fi

# Test: Generated script has valid bash syntax
if bash -n out/install.sh 2>/dev/null; then
    test_pass "out/install.sh has valid bash syntax"
else
    test_fail "out/install.sh has syntax errors"
fi

# Test: Generated script has required components
if grep -q "#!/usr/bin/env bash" out/install.sh; then
    test_pass "Shebang present in output"
else
    test_fail "Shebang missing in output"
fi

if grep -q "^function update_script" out/install.sh; then
    test_pass "update_script function present"
else
    test_fail "update_script function missing"
fi

if grep -q "build.func" out/install.sh && \
   grep -q "source <(curl" out/install.sh; then
    test_pass "Proxmox build.func sourced"
else
    test_fail "Proxmox build.func not sourced"
fi

# Test: Security script embedded
if grep -q "elk-configure-security.sh" out/install.sh; then
    test_pass "Security configuration script embedded"
else
    test_fail "Security configuration script not embedded"
fi

# Test: Rotation script embedded
if grep -q "elk-rotate-api-keys.sh" out/install.sh; then
    test_pass "API key rotation script embedded"
else
    test_fail "API key rotation script not embedded"
fi

# Test: EOFSCRIPT markers are balanced
EOFSCRIPT_COUNT=$(grep -c "EOFSCRIPT" out/install.sh || echo 0)
if [[ $((EOFSCRIPT_COUNT % 2)) -eq 0 ]]; then
    test_pass "EOFSCRIPT markers balanced ($EOFSCRIPT_COUNT markers)"
else
    test_fail "EOFSCRIPT markers unbalanced ($EOFSCRIPT_COUNT markers)"
fi

# Test: All installation steps present
EXPECTED_STEPS=(
    "Installing Dependencies"
    "Adding Elastic Repository"
    "Updating Package Lists"
    "Installing ELK Stack"
    "Preparing Elasticsearch Directories"
    "Deploying Elasticsearch Configuration"
    "Preparing Logstash Directories"
    "Deploying Logstash Configuration"
    "Deploying Kibana Configuration"
    "Generating Keystore Passwords"
    "Initializing Kibana Keystore"
    "Initializing Logstash Keystore"
    "Enabling Services"
)
MISSING_STEPS=0
for step in "${EXPECTED_STEPS[@]}"; do
    if grep -q "$step" out/install.sh; then
        test_pass "Step present: $step"
    else
        test_fail "Step missing: $step"
        ((MISSING_STEPS++))
    fi
done

test_header "Structure Validation"

# Test: msg_info and msg_ok calls are balanced
MSG_INFO_TOTAL=$(grep -c "msg_info" out/install.sh || echo 0)
MSG_OK_TOTAL=$(grep -c "msg_ok" out/install.sh || echo 0)

if [[ $MSG_INFO_TOTAL -gt 0 ]]; then
    test_pass "msg_info calls present ($MSG_INFO_TOTAL total)"
else
    test_fail "No msg_info calls found"
fi

if [[ $MSG_OK_TOTAL -gt 0 ]]; then
    test_pass "msg_ok calls present ($MSG_OK_TOTAL total)"
else
    test_fail "No msg_ok calls found"
fi

# Test: File size is reasonable (should be between 200-1000 lines)
LINE_COUNT=$(wc -l < out/install.sh | tr -d ' ')
if [[ $LINE_COUNT -ge 200 && $LINE_COUNT -le 1000 ]]; then
    test_pass "Generated script size reasonable ($LINE_COUNT lines)"
else
    test_fail "Generated script size unexpected ($LINE_COUNT lines)"
fi

test_header "Content Validation"

# Test: No placeholder text remains
if grep -qi "TODO\|FIXME\|XXX" out/install.sh; then
    test_fail "Placeholder text found in output"
else
    test_pass "No placeholder text in output"
fi

# Test: Copyright and license headers present
if grep -q "Copyright.*Alex Goodkind" out/install.sh; then
    test_pass "Copyright header present"
else
    test_fail "Copyright header missing"
fi

if grep -q "License.*Apache-2.0" out/install.sh; then
    test_pass "License header present"
else
    test_fail "License header missing"
fi

# Test: Essential Proxmox variables defined
REQUIRED_VARS="var_cpu var_ram var_disk var_os var_version"
for var in $REQUIRED_VARS; do
    if grep -q "$var=" out/install.sh; then
        test_pass "Variable defined: $var"
    else
        test_fail "Variable missing: $var"
    fi
done

# Test: Essential Proxmox functions called
REQUIRED_CALLS="header_info variables color catch_errors start build_container description"
for func in $REQUIRED_CALLS; do
    if grep -q "$func" out/install.sh; then
        test_pass "Function called: $func"
    else
        test_fail "Function call missing: $func"
    fi
done

# Print summary
test_header "Test Summary"
echo ""
echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
else
    echo -e "Tests failed: $TESTS_FAILED"
fi
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     ALL TESTS PASSED ✓                 ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    exit 0
else
    echo -e "${RED}╔════════════════════════════════════════╗${NC}"
    echo -e "${RED}║     TESTS FAILED ✗                     ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════╝${NC}"
    exit 1
fi

