#!/usr/bin/env bash
# Copyright (c) 2025 Alex Goodkind
# Author: Alex Goodkind (agoodkind)
# License: Apache-2.0
#
# ELK Stack Installation Script - Single Source of Truth
#
# This script installs and configures the full ELK Stack
# (Elasticsearch, Logstash, Kibana) on Ubuntu 24.04.
# It works in two modes:
#
# Execution Modes:
# 1. Proxmox community script: Inherits framework's msg_* and $STD functions
# 2. Template build: Pre-set variables (NON_INTERACTIVE, etc.) for non-interactive install
# 3. Standalone: Uses fallback shims for msg_* and silent() functions
#
# The shim pattern allows the same installation logic to work
# in all modes with automatic detection.

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================

# Step counter (auto-increments with each step)
STEP=0

# ============================================================================
# INTERACTIVE CONFIGURATION
# ============================================================================

# Define TAB3 if not already set (for standalone mode)
TAB3="${TAB3:-   }"

# Define silent function if not already defined (from Proxmox framework)
if ! command -v silent &> /dev/null; then
    silent() {
        "$@" >/dev/null 2>&1
    }
fi

# Define verbose logging function
msg_verbose() {
    if [ "${VERBOSE}" = "yes" ] || [ "${var_verbose}" = "yes" ]; then
        echo "$@"
    fi
}

# Define debug function to show file contents
msg_debug() {
    if [ "${DEBUG}" = "true" ]; then
        local msg="$1"
        local file="$2"
        if [ -n "$file" ] && [ -f "$file" ]; then
            local file_content=$(grep -v "^#" "$file" | grep -v "^$" | head -20 | sed 's/^/DEBUG      /' || echo "DEBUG      (empty or all comments)")
            echo -e "DEBUG: $msg\n---\n$file_content"
        elif [ -n "$file" ]; then
            echo "DEBUG: $msg (file $file doesn't exist)"
        else
            echo "DEBUG: $msg"
        fi
    fi
}

# Define error logging function
msg_error() {
    if [ -n "${LOG_FILE:-}" ]; then
        echo "✗ ERROR: $*" | tee -a "$LOG_FILE"
    else
        echo "✗ ERROR: $*"
    fi
}

# Set STD if not already defined (Proxmox framework sets this)
if [ -z "$STD" ]; then
    if [ "${VERBOSE}" = "yes" ] || [ "${var_verbose}" = "yes" ]; then
        STD=""  # Verbose mode: show all output

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "VERBOSE MODE ENABLED"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Environment Variables:"
        echo "  NON_INTERACTIVE: ${NON_INTERACTIVE:-<not set>}"
        echo "  VERBOSE: ${VERBOSE:-<not set>}"
        echo "  var_verbose: ${var_verbose:-<not set>}"
        echo "  DEBUG: ${DEBUG:-<not set>}"
        echo "  APPLICATION: ${APPLICATION:-<not set>}"
        echo "  app: ${app:-<not set>}"
        echo "  CTID: ${CTID:-<not set>}"
        echo "  STD: ${STD:-<empty/verbose>}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    else
        STD="silent"  # Quiet mode: use silent function
    fi
fi

# Check if running interactively for memory customization
if [ "${NON_INTERACTIVE:-false}" = "true" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "NON-INTERACTIVE MODE (with verbose logging)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Using default configuration:"
    echo "  → Security: Enabled (Elasticsearch auto-configured)"
    echo "  → SSL: Enabled (auto-generated certificates)"
    echo "  → Elasticsearch Heap: 2GB"
    echo "  → Logstash Heap: 1GB"
    echo "  → Verbose logging: Enabled"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    CUSTOMIZE_MEMORY=no
fi

if [ -z "$CUSTOMIZE_MEMORY" ] && [ "${NON_INTERACTIVE:-false}" != "true" ]; then
  echo
  read -rp "${TAB3}Customize JVM heap sizes? (default: Elasticsearch 2GB, Logstash 1GB) [y/N]: " CUSTOMIZE_MEMORY </dev/tty
fi

if [[ ${CUSTOMIZE_MEMORY,,} =~ ^(y|yes)$ ]]; then
  if [ -z "$ES_HEAP_GB" ]; then
    echo "${TAB3}Memory Configuration:"
    read -rp "${TAB3}Elasticsearch heap size in GB (default: 2): " ES_HEAP_GB </dev/tty
  fi
  ES_HEAP_GB=${ES_HEAP_GB:-2}
  
  if [ -z "$LS_HEAP_GB" ]; then
    read -rp "${TAB3}Logstash heap size in GB (default: 1): " LS_HEAP_GB </dev/tty
  fi
  LS_HEAP_GB=${LS_HEAP_GB:-1}
else
  ES_HEAP_GB=2
  LS_HEAP_GB=1
fi

msg_verbose "Final configuration:"
msg_verbose "  → Security + SSL: Always enabled (Elasticsearch auto-config)"
msg_verbose "  → Elasticsearch Heap: ${ES_HEAP_GB}GB"
msg_verbose "  → Logstash Heap: ${LS_HEAP_GB}GB"
msg_verbose ""

echo

# ============================================================================
# LOGGING SETUP
# ============================================================================

# Initialize logging (if not already set by caller)
# Proxmox framework will define LOG_FILE, standalone mode uses default
LOG_FILE="${LOG_FILE:-/var/log/elk-install.log}"
if [ ! -f "$LOG_FILE" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - \
Starting ELK Stack installation" | tee "$LOG_FILE"
    echo "Installation log: $LOG_FILE" | tee -a "$LOG_FILE"
fi

# ============================================================================
# SHIM FUNCTIONS
# ============================================================================
# These functions provide a consistent interface for both execution modes.
# Proxmox framework defines these in install-header.sh with colored output.
# Standalone mode defines simple versions here with logging.

# Display informational message at start of installation step
if ! command -v msg_info &> /dev/null; then
    msg_info() {
        echo "" | tee -a "$LOG_FILE"
        echo "▶ $1" | tee -a "$LOG_FILE"
    }
fi

# Display success message at end of installation step
if ! command -v msg_ok &> /dev/null; then
    msg_ok() {
        echo "✓ $1" | tee -a "$LOG_FILE"
    }
fi

# ============================================================================
# STEP WRAPPER FUNCTIONS
# ============================================================================
# Wrapper functions that auto-increment step counter and format messages

# Start a new installation step
step_start() {
    STEP=$((STEP + 1))
    msg_info "[$STEP] $1"
}

# Complete an installation step
step_done() {
    msg_ok "[$STEP] ${1:-Completed}"
}

# Configuration is now embedded inline (no external files needed)

# ============================================================================
# INSTALLATION STEPS
# ============================================================================

# ----------------------------------------------------------------------------
# Update repositories
# ----------------------------------------------------------------------------
step_start "Update repositories"
if ! $STD apt-get update; then
    msg_error "Failed to update repositories"
    exit 1
fi
step_done "Updated repositories"

# ----------------------------------------------------------------------------
# Install System Dependencies
# ----------------------------------------------------------------------------
step_start "Installing Dependencies"
# Required: wget (download GPG key), gnupg (process GPG),
#   apt-transport-https & ca-certificates (HTTPS repos),
#   openjdk-11 (Java for ELK), curl (API calls),
#   unzip & openssl (SSL cert management)
if ! $STD apt-get install -y \
    wget gnupg apt-transport-https ca-certificates \
    openjdk-11-jre-headless curl unzip openssl \
    htop net-tools vim; then
    msg_error "Failed to install dependencies"
    exit 1
fi
step_done "Installed Dependencies"

# ----------------------------------------------------------------------------
# Add Elastic Repository
# ----------------------------------------------------------------------------
step_start "Adding Elastic Repository"
# Download and install Elastic GPG key (don't use $STD - needs stdout for pipe)
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch 2>/dev/null | \
    gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg 2>/dev/null

# Add Elastic 8.x repository
echo "deb \
[signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] \
https://artifacts.elastic.co/packages/8.x/apt stable main" \
    > /etc/apt/sources.list.d/elastic-8.x.list
step_done "Added Elastic Repository"

# ----------------------------------------------------------------------------
# Update Package Lists
# ----------------------------------------------------------------------------
step_start "Updating Package Lists"
# Update package list to include Elastic repository
$STD apt-get update
step_done "Updated Package Lists"

# ----------------------------------------------------------------------------
# Install ELK Stack Packages
# ----------------------------------------------------------------------------
step_start "Installing ELK Stack (Elasticsearch, Logstash, Kibana)"
msg_verbose "  → Downloading packages (~2GB, may take 5-15 minutes)..."
# Log download information
echo "$(date '+%Y-%m-%d %H:%M:%S') - Downloading ~2GB, \
takes 5-15 minutes depending on network speed" | tee -a "$LOG_FILE"
# Install all three ELK components
if ! DEBIAN_FRONTEND=noninteractive apt-get install -qq -y elasticsearch logstash kibana ; then
    msg_error "Failed to install ELK Stack packages"
    exit 1
fi
step_done "Installed ELK Stack (Elasticsearch, Logstash, Kibana)"

# ----------------------------------------------------------------------------
# Prepare Elasticsearch Directories
# ----------------------------------------------------------------------------
step_start "Preparing Elasticsearch Directories"
msg_debug "Existing JVM options" /etc/elasticsearch/jvm.options
msg_debug "Existing elasticsearch.yml" /etc/elasticsearch/elasticsearch.yml
mkdir -p /etc/elasticsearch/jvm.options.d
step_done "Prepared Elasticsearch Directories"

# ----------------------------------------------------------------------------
# Configure Elasticsearch JVM Heap (only)
# ----------------------------------------------------------------------------
# We don't touch elasticsearch.yml before startup - let auto-config handle everything
# Network settings will be configured after auto-config completes
step_start "Configuring Elasticsearch JVM Heap"

cat > /etc/elasticsearch/jvm.options.d/heap.options << EOF
# JVM heap settings for Elasticsearch
-Xms${ES_HEAP_GB:-2}g
-Xmx${ES_HEAP_GB:-2}g
EOF
step_done "Configured Elasticsearch JVM Heap"

# ----------------------------------------------------------------------------
# Prepare Logstash Directories
# ----------------------------------------------------------------------------
step_start "Preparing Logstash Directories"
mkdir -p /etc/logstash/conf.d
mkdir -p /etc/logstash/jvm.options.d
step_done "Prepared Logstash Directories"

# ----------------------------------------------------------------------------
# Deploy Logstash Configuration
# ----------------------------------------------------------------------------
step_start "Deploying Logstash Configuration"
msg_verbose "  → Configuring Logstash JVM heap size..."

# Configure heap size
cat > /etc/logstash/jvm.options.d/heap.options << EOF
# JVM heap settings for Logstash
-Xms${LS_HEAP_GB:-1}g
-Xmx${LS_HEAP_GB:-1}g
EOF

# Note: Pipelines are configured for HTTPS with API key authentication
# Users can add custom pipelines to /etc/logstash/conf.d/ after installation
step_done "Deployed Logstash Configuration"

# ----------------------------------------------------------------------------
# Deploy Kibana Configuration
# ----------------------------------------------------------------------------
step_start "Deploying Kibana Configuration"
msg_verbose "  → Writing Kibana configuration to /etc/kibana/kibana.yml..."

# Comment out default settings that we'll override to avoid duplicates
msg_verbose "  → Removing default settings to avoid duplicates..."
sed -i 's/^server.port:/#&/' /etc/kibana/kibana.yml
sed -i 's/^server.host:/#&/' /etc/kibana/kibana.yml
sed -i 's/^elasticsearch.hosts:/#&/' /etc/kibana/kibana.yml
sed -i 's/^elasticsearch.username:/#&/' /etc/kibana/kibana.yml
sed -i 's/^elasticsearch.password:/#&/' /etc/kibana/kibana.yml

# Append our configuration
msg_verbose "  → Appending custom configuration..."
cat >> /etc/kibana/kibana.yml << 'EOF'

# ============================================================================
# Custom Kibana Configuration
# ============================================================================

# Kibana server configuration
server.port: 5601
# Prefer IPv6 and listen on all interfaces
server.host: "::"

# Elasticsearch connection will be auto-configured via enrollment token
# (kibana-setup will add elasticsearch.hosts, SSL settings, and authentication)
EOF
step_done "Deployed Kibana Configuration"

# ----------------------------------------------------------------------------
# Generate Keystore Passwords
# ----------------------------------------------------------------------------
step_start "Generating Keystore Passwords"
msg_verbose "  → Generating secure password for Logstash keystore..."
# Generate secure random password for Logstash keystore (required v8+)
LOGSTASH_KEYSTORE_PASS=$(openssl rand -base64 32)

# Store in /etc/default/logstash for systemd service
echo "LOGSTASH_KEYSTORE_PASS=\"${LOGSTASH_KEYSTORE_PASS}\"" \
    > /etc/default/logstash
chown root:root /etc/default/logstash
chmod 0600 /etc/default/logstash

# Add to root's environment for interactive sessions
msg_verbose "  → Adding Logstash keystore password to /root/.bashrc..."
if ! grep -q "LOGSTASH_KEYSTORE_PASS" /root/.bashrc; then
    echo "" >> /root/.bashrc
    echo "# Logstash keystore password" >> /root/.bashrc
    echo "export LOGSTASH_KEYSTORE_PASS=\"\
${LOGSTASH_KEYSTORE_PASS}\"" >> /root/.bashrc
    msg_verbose "  ✓ Added to .bashrc"
fi

# Export for current session
export LOGSTASH_KEYSTORE_PASS
msg_verbose "  ✓ Password exported to current session"
msg_verbose "  ✓ Password length: ${#LOGSTASH_KEYSTORE_PASS} characters"

step_done "Generated Keystore Passwords"

# ----------------------------------------------------------------------------
# Initialize Logstash Keystore
# ----------------------------------------------------------------------------
# Note: Elasticsearch and Kibana keystores are auto-created
#   - Elasticsearch: auto-config creates it on first startup
#   - Kibana: enrollment token (kibana-setup) creates it
#   - Logstash: must be created manually (no auto-config)
step_start "Initializing Logstash Keystore"
msg_verbose "  → Removing any existing Logstash keystore..."
rm -f /etc/logstash/logstash.keystore
msg_verbose "  → Creating new Logstash keystore with password..."
msg_verbose "  → Using path: /etc/logstash"
if [ "$VERBOSE" = "yes" ]; then
    /usr/share/logstash/bin/logstash-keystore \
        --path.settings /etc/logstash create
else
    /usr/share/logstash/bin/logstash-keystore \
        --path.settings /etc/logstash create >/dev/null 2>&1
fi
msg_verbose "  → Setting ownership to logstash:root"
chown logstash:root /etc/logstash/logstash.keystore
msg_verbose "  → Setting permissions to 0600"
chmod 0600 /etc/logstash/logstash.keystore
msg_verbose "  ✓ Keystore created at /etc/logstash/logstash.keystore"
if [ "$VERBOSE" = "yes" ]; then
    ls -lh /etc/logstash/logstash.keystore
fi
step_done "Initialized Logstash Keystore"

# ----------------------------------------------------------------------------
# SSL + Security Auto-Configuration
# ----------------------------------------------------------------------------
# Elasticsearch will auto-configure security + SSL on first startup:
#   - Generates: http_ca.crt, http.p12, transport.p12
#   - Configures: elasticsearch.yml with SSL settings
#   - Creates: elasticsearch.keystore with passwords
#   - Sets: elastic user password (we reset it below)
#   - Enables: enrollment token generation

# ----------------------------------------------------------------------------
# Start Elasticsearch (needed for user/key creation)
# ----------------------------------------------------------------------------
step_start "Starting Elasticsearch"
msg_verbose "  → Enabling Elasticsearch service..."
$STD systemctl enable elasticsearch
msg_verbose "  → Starting Elasticsearch service..."
$STD systemctl start elasticsearch
msg_verbose "  → Waiting 30 seconds for Elasticsearch to initialize..."
sleep 30
msg_verbose "  → Checking Elasticsearch status..."
if [ "$VERBOSE" = "yes" ]; then
    systemctl status elasticsearch --no-pager || true
fi
step_done "Started Elasticsearch"

# ----------------------------------------------------------------------------
# Copy CA Certificate for Logstash
# ----------------------------------------------------------------------------
# Note: Kibana will be auto-configured via enrollment token
# Logstash needs the CA cert for connecting to Elasticsearch
step_start "Preparing Logstash SSL"
msg_verbose "  → Waiting for Elasticsearch auto-generated certificates..."

# Wait for ES to generate certificates (auto-config happens on first startup)
MAX_WAIT=60
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    msg_verbose "  → Checking for Elasticsearch auto-generated certificates... ($WAIT_COUNT/$MAX_WAIT)"
    if [ -f /etc/elasticsearch/certs/http_ca.crt ]; then
        msg_verbose "  ✓ Certificates found"
        break
    fi
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 2))
done

if [ ! -f /etc/elasticsearch/certs/http_ca.crt ]; then
    msg_error "Auto-generated certificates not found after waiting"
    exit 1
fi

# Copy http_ca.crt for Logstash (Kibana handled by enrollment token)
msg_verbose "  → Copying http_ca.crt for Logstash..."
mkdir -p /etc/logstash/certs
cp /etc/elasticsearch/certs/http_ca.crt /etc/logstash/certs/ca.crt
chmod 640 /etc/logstash/certs/ca.crt
chown logstash:logstash /etc/logstash/certs/ca.crt
msg_verbose "  ✓ Logstash SSL prepared"
step_done "Prepared Logstash SSL"

# ----------------------------------------------------------------------------
# Configure Elasticsearch Network Settings (after auto-config)
# ----------------------------------------------------------------------------
step_start "Configuring Elasticsearch Network Settings"
msg_verbose "  → Adding network configuration to elasticsearch.yml..."
msg_debug "Existing elasticsearch.yml" /etc/elasticsearch/elasticsearch.yml
# Comment out any existing network.host and cluster.name (from auto-config or defaults)
sed -i 's/^network.host:/#&/' /etc/elasticsearch/elasticsearch.yml
sed -i 's/^cluster.name:/#&/' /etc/elasticsearch/elasticsearch.yml

# Now that auto-config has completed, add our network settings
# Use APPLICATION variable for cluster name (follows Proxmox patterns)
CLUSTER_NAME="${APPLICATION:-ELK-Stack}"
cat >> /etc/elasticsearch/elasticsearch.yml << EOF

# Network configuration (added after auto-config)
# Prefer IPv6 and listen on all interfaces
network.host:
  - "::"
  - "0.0.0.0"

# Cluster identification (uses APPLICATION variable)
cluster.name: ${CLUSTER_NAME}
EOF

msg_verbose "  → Restarting Elasticsearch to apply network changes..."
$STD systemctl restart elasticsearch
msg_verbose "  → Waiting for Elasticsearch to be ready..."
# Wait for Elasticsearch to be ready (can take 15-30 seconds after restart)
MAX_WAIT=60
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if curl -k -s -o /dev/null -w "%{http_code}" https://localhost:9200 | grep -qE "(200|401|403)"; then
        msg_verbose "  ✓ Elasticsearch is ready"
        break
    fi
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 2))
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
    msg_error "Elasticsearch did not become ready after restart"
    exit 1
fi
msg_verbose "  ✓ Elasticsearch restarted with new network settings"
step_done "Configured Elasticsearch Network Settings"

# ----------------------------------------------------------------------------
# Set Elasticsearch URL (always HTTPS with auto-config)
# ----------------------------------------------------------------------------
ES_URL="https://localhost:9200"
CURL_OPTS="-k"

# ----------------------------------------------------------------------------
# Generate Elastic Password (always needed - security is always enabled)
# ----------------------------------------------------------------------------
step_start "Generating Elastic Password"
msg_verbose "  → Generating random password for elastic user..."
ELASTIC_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)
msg_verbose "  → Resetting elastic user password..."
if [ "$VERBOSE" = "yes" ]; then
    echo "$ELASTIC_PASSWORD" | /usr/share/elasticsearch/bin/elasticsearch-reset-password \
        -u elastic -b -s -i
else
    echo "$ELASTIC_PASSWORD" | /usr/share/elasticsearch/bin/elasticsearch-reset-password \
        -u elastic -b -s -i >/dev/null 2>&1
fi
step_done "Generated Elastic Password"

# ----------------------------------------------------------------------------
# Configure Kibana with Enrollment Token
# ----------------------------------------------------------------------------
step_start "Configuring Kibana with Enrollment Token"
msg_verbose "  → Creating enrollment token for Kibana..."

# Generate enrollment token (auto-config creates these)
if [ ! -f /usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token ]; then
    msg_error "elasticsearch-create-enrollment-token not found (auto-config may not have run)"
    msg_verbose "  → Ensure Elasticsearch auto-config ran on first startup"
    exit 1
fi

ENROLLMENT_TOKEN=$(/usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana 2>/dev/null || echo "")

if [ -z "$ENROLLMENT_TOKEN" ]; then
    msg_error "Failed to generate Kibana enrollment token"
    msg_verbose "  → Check if xpack.security.enrollment.enabled is true"
    msg_verbose "  → Check Elasticsearch logs for auto-configuration errors"
    exit 1
fi
msg_verbose "  ✓ Enrollment token created (length: ${#ENROLLMENT_TOKEN} chars)"

# Use kibana-setup to apply enrollment token non-interactively
msg_verbose "  → Applying enrollment token to Kibana configuration..."
if [ "$VERBOSE" = "yes" ]; then
    if ! echo "$ENROLLMENT_TOKEN" | /usr/share/kibana/bin/kibana-setup --enrollment-token; then
        msg_error "Failed to apply enrollment token to Kibana"
        exit 1
    fi
else
    if ! echo "$ENROLLMENT_TOKEN" | /usr/share/kibana/bin/kibana-setup --enrollment-token >/dev/null 2>&1; then
        msg_error "Failed to apply enrollment token to Kibana"
        exit 1
    fi
fi

msg_verbose "  ✓ Enrollment token applied (Kibana auto-configured)"
step_done "Configured Kibana with Enrollment Token"

# ----------------------------------------------------------------------------
# Create Logstash API Key
# ----------------------------------------------------------------------------
step_start "Creating Logstash API Key"
msg_verbose "  → Defining Logstash writer role with permissions for logs-*, logstash-*, ecs-*"
LOGSTASH_ROLE='{"name":"logstash_writer","role_descriptors":{"logstash_writer":{"cluster":["monitor","manage_index_templates","manage_ilm"],"indices":[{"names":["logs-*","logstash-*","ecs-*"],"privileges":["write","create","create_index","manage","manage_ilm"]}]}}}'
msg_verbose "  → Creating API key via Elasticsearch API..."
msg_verbose "  → Endpoint: $ES_URL/_security/api_key"
LOGSTASH_KEY_RESPONSE=$(curl $CURL_OPTS -s -X POST \
    "$ES_URL/_security/api_key" \
    -u "elastic:$ELASTIC_PASSWORD" \
    -H "Content-Type: application/json" \
    -d "$LOGSTASH_ROLE")
LOGSTASH_API_KEY=$(echo "$LOGSTASH_KEY_RESPONSE" | grep -o '"encoded":"[^"]*' | cut -d'"' -f4)

if [ -z "$LOGSTASH_API_KEY" ]; then
    msg_error "Failed to extract API key from Elasticsearch response"
    msg_verbose "  → Response: $LOGSTASH_KEY_RESPONSE"
    exit 1
fi
msg_verbose "  ✓ Logstash API key created (length: ${#LOGSTASH_API_KEY} chars)"
if [ "$VERBOSE" = "yes" ]; then
    msg_verbose "  ✓ API key successfully extracted from response"
fi
step_done "Created Logstash API Key"

# ----------------------------------------------------------------------------
# Configure Logstash Keystore
# ----------------------------------------------------------------------------
step_start "Configuring Logstash Keystore"
msg_verbose "  → Adding Logstash API key to keystore (ELASTICSEARCH_API_KEY)..."
if [ "$VERBOSE" = "yes" ]; then
    echo "$LOGSTASH_API_KEY" | /usr/share/logstash/bin/logstash-keystore \
        --path.settings /etc/logstash \
        add ELASTICSEARCH_API_KEY --stdin --force
else
    echo "$LOGSTASH_API_KEY" | /usr/share/logstash/bin/logstash-keystore \
        --path.settings /etc/logstash \
        add ELASTICSEARCH_API_KEY --stdin --force >/dev/null 2>&1
fi
msg_verbose "  ✓ API key added to keystore"
msg_verbose "  → Setting keystore ownership and permissions..."
chown logstash:root /etc/logstash/logstash.keystore
chmod 0600 /etc/logstash/logstash.keystore
msg_verbose "  ✓ Keystore configured with secure permissions"
if [ "$VERBOSE" = "yes" ]; then
    msg_verbose "  → Listing keystore keys:"
    /usr/share/logstash/bin/logstash-keystore --path.settings /etc/logstash list
fi
step_done "Configured Logstash Keystore"

# ----------------------------------------------------------------------------
# Configure Logstash Output
# ----------------------------------------------------------------------------
step_start "Configuring Logstash Output"
cat > /etc/logstash/conf.d/30-output.conf << 'EOF'

# Logstash output configuration (HTTPS with API key)
output {
	elasticsearch {
		hosts => ["https://[::1]:9200"]
		api_key => "${ELASTICSEARCH_API_KEY}"
		index => "%{[@metadata][beat]}-%{[@metadata][version]}-%{+YYYY.MM.dd}"
		ssl => true
		cacert => "/etc/logstash/certs/ca.crt"
	}
}
EOF
step_done "Configured Logstash Output"

# Kibana connection is auto-configured by enrollment token
# (kibana-setup wrote elasticsearch.hosts, SSL settings, and authentication to kibana.yml)
# No manual configuration needed

# ----------------------------------------------------------------------------
# Save Credentials
# ----------------------------------------------------------------------------
step_start "Saving Credentials"
KIBANA_URL="https://$(hostname -I | awk '{print $1}'):5601"

msg_verbose "  → Writing credentials to /root/elk-credentials.txt..."
msg_verbose "  → Kibana URL: $KIBANA_URL"
msg_verbose "  → Username: elastic"
msg_verbose "  → Password length: ${#ELASTIC_PASSWORD} characters"
cat > /root/elk-credentials.txt << EOF
ELK Stack Credentials
=====================
Kibana URL: $KIBANA_URL
Username: elastic
Password: $ELASTIC_PASSWORD

Security Notes:
- SSL/HTTPS enabled (auto-configured by Elasticsearch)
- Self-signed certificates (suitable for internal use)
- API keys stored in keystores
- Certificates: /etc/elasticsearch/certs/ (auto-generated)

Management:
- Reset password: /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic
- Restart services: systemctl restart elasticsearch logstash kibana
EOF
chmod 600 /root/elk-credentials.txt
step_done "Saved Credentials"

# ----------------------------------------------------------------------------
# Enable and Start Services
# ----------------------------------------------------------------------------
step_start "Starting Services"
msg_verbose "  → Enabling Logstash and Kibana services..."
$STD systemctl enable logstash kibana
msg_verbose "  → Starting Logstash and Kibana services..."
$STD systemctl start logstash kibana
msg_verbose "  → Checking service status..."
if [ "$VERBOSE" = "yes" ]; then
    systemctl status logstash --no-pager || true
    systemctl status kibana --no-pager || true
fi
step_done "Started Services"

# ============================================================================
# INSTALLATION COMPLETE
# ============================================================================
msg_ok "Completed Successfully!"
msg_info "Installation log saved to: $LOG_FILE (inside container)"
msg_info "View credentials: cat /root/elk-credentials.txt"
msg_info "Access Kibana: $KIBANA_URL"

# Write final log message
echo "" | tee -a "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - \
ELK Stack installation completed successfully" \
    | tee -a "$LOG_FILE"
echo "Installation log saved to: $LOG_FILE (inside container)" \
    | tee -a "$LOG_FILE"
