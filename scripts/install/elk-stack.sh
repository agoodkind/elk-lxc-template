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
# 2. Template build: Pre-set variables (SSL_CHOICE, etc.) for non-interactive install
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

# Check if running interactively or if variables pre-set (template build mode)
if [ -z "$SSL_CHOICE" ]; then
  # Check for non-interactive mode
  if [ "${NON_INTERACTIVE:-false}" == "true" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "NON-INTERACTIVE MODE (with verbose logging)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Using default configuration:"
    echo "  → SSL Choice: 1 (Full HTTPS - Elasticsearch + Kibana)"
    echo "  → Elasticsearch Heap: 2GB"
    echo "  → Logstash Heap: 1GB"
    echo "  → Verbose logging: Enabled"
    echo "  → Self-signed certificates: Will be generated"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    SSL_CHOICE=1
    CUSTOMIZE_MEMORY=no
  else
    echo
    echo "${TAB3}━━━ ELK Stack Configuration ━━━"
    echo
    echo "${TAB3}Note: HTTPS uses self-signed certificates (suitable for internal use)"
    echo
    echo "${TAB3}SSL/TLS Configuration:"
    echo "${TAB3}[1] Full HTTPS (Elasticsearch + Kibana) [Recommended]"
    echo "${TAB3}[2] Backend only (Elasticsearch HTTPS, Kibana HTTP)"
    echo "${TAB3}[3] No SSL (HTTP only - testing/dev)"

    read -rp "${TAB3}Enter your choice (default: 1): " SSL_CHOICE </dev/tty
    SSL_CHOICE=${SSL_CHOICE:-1}
  fi
fi

case $SSL_CHOICE in
1)
  ENABLE_BACKEND_SSL=true
  ENABLE_FRONTEND_SSL=true
  ;;
2)
  ENABLE_BACKEND_SSL=true
  ENABLE_FRONTEND_SSL=false
  ;;
3)
  ENABLE_BACKEND_SSL=false
  ENABLE_FRONTEND_SSL=false
  ;;
*)
  echo "${TAB3}Invalid choice. Using Full HTTPS."
  ENABLE_BACKEND_SSL=true
  ENABLE_FRONTEND_SSL=true
  ;;
esac

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
msg_verbose "  → SSL Backend: ${ENABLE_BACKEND_SSL}"
msg_verbose "  → SSL Frontend: ${ENABLE_FRONTEND_SSL}"
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
if [ "$VERBOSE" = "yes" ]; then
    if ! apt-get install -y elasticsearch logstash kibana; then
        msg_error "Failed to install ELK Stack packages"
        exit 1
    fi
else
    if ! $STD apt-get install -y elasticsearch logstash kibana; then
        msg_error "Failed to install ELK Stack packages"
        exit 1
    fi
fi
step_done "Installed ELK Stack (Elasticsearch, Logstash, Kibana)"

# ----------------------------------------------------------------------------
# Prepare Elasticsearch Directories
# ----------------------------------------------------------------------------
step_start "Preparing Elasticsearch Directories"
mkdir -p /etc/elasticsearch/jvm.options.d
step_done "Prepared Elasticsearch Directories"

# ----------------------------------------------------------------------------
# Deploy Elasticsearch Configuration
# ----------------------------------------------------------------------------
step_start "Deploying Elasticsearch Configuration"
msg_verbose "  → Writing Elasticsearch configuration to /etc/elasticsearch/elasticsearch.yml..."

# Comment out default settings that we'll override to avoid duplicates
msg_verbose "  → Removing default settings to avoid duplicates..."
sed -i 's/^xpack.security.enabled:/#&/' /etc/elasticsearch/elasticsearch.yml
sed -i 's/^xpack.security.enrollment.enabled:/#&/' /etc/elasticsearch/elasticsearch.yml
sed -i 's/^xpack.security.http.ssl.enabled:/#&/' /etc/elasticsearch/elasticsearch.yml
sed -i 's/^xpack.security.http.ssl.keystore.path:/#&/' /etc/elasticsearch/elasticsearch.yml
sed -i 's/^xpack.security.http.ssl.key:/#&/' /etc/elasticsearch/elasticsearch.yml
sed -i 's/^xpack.security.transport.ssl.enabled:/#&/' /etc/elasticsearch/elasticsearch.yml
sed -i 's/^xpack.security.transport.ssl.keystore.path:/#&/' /etc/elasticsearch/elasticsearch.yml
sed -i 's/^xpack.security.transport.ssl.truststore.path:/#&/' /etc/elasticsearch/elasticsearch.yml
sed -i 's/^xpack.security.transport.ssl.verification_mode:/#&/' /etc/elasticsearch/elasticsearch.yml
sed -i 's/^cluster.name:/#&/' /etc/elasticsearch/elasticsearch.yml
sed -i 's/^node.name:/#&/' /etc/elasticsearch/elasticsearch.yml
sed -i 's/^network.host:/#&/' /etc/elasticsearch/elasticsearch.yml
sed -i 's/^http.port:/#&/' /etc/elasticsearch/elasticsearch.yml
sed -i 's/^cluster.initial_master_nodes:/#&/' /etc/elasticsearch/elasticsearch.yml

# Append our configuration
msg_verbose "  → Appending custom configuration..."
cat >> /etc/elasticsearch/elasticsearch.yml << 'EOF'

# ============================================================================
# Custom ELK Stack Configuration
# ============================================================================

# Elasticsearch network configuration
# Prefer IPv6 and listen on all interfaces
network.host:
  - "::"
  - "0.0.0.0"
http.port: 9200

# Cluster and node settings
cluster.name: elk-cluster
node.name: ${HOSTNAME}

# Enable security with SSL
xpack.security.enabled: true
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.keystore.path: certs/http.p12
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.keystore.path: certs/transport.p12
xpack.security.transport.ssl.truststore.path: certs/transport.p12
xpack.security.transport.ssl.verification_mode: certificate
EOF

# Configure heap size based on user input
cat > /etc/elasticsearch/jvm.options.d/heap.options << EOF

# JVM heap settings for Elasticsearch
-Xms${ES_HEAP_GB:-2}g
-Xmx${ES_HEAP_GB:-2}g
EOF
step_done "Deployed Elasticsearch Configuration"

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

# Note: Pipelines will be configured based on SSL choice
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

# Elasticsearch connection will be configured based on SSL choice
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
# Initialize Keystores
# ----------------------------------------------------------------------------
step_start "Initializing Kibana Keystore"
msg_verbose "  → Removing any existing Kibana keystore..."
rm -f /etc/kibana/kibana.keystore
msg_verbose "  → Setting KBN_PATH_CONF=/etc/kibana"
export KBN_PATH_CONF=/etc/kibana
msg_verbose "  → Creating new Kibana keystore..."
if [ "$VERBOSE" = "yes" ]; then
    /usr/share/kibana/bin/kibana-keystore create
else
    /usr/share/kibana/bin/kibana-keystore create >/dev/null 2>&1
fi
msg_verbose "  → Setting ownership to kibana:root"
chown kibana:root /etc/kibana/kibana.keystore
msg_verbose "  → Setting permissions to 0600"
chmod 0600 /etc/kibana/kibana.keystore
msg_verbose "  ✓ Keystore created at /etc/kibana/kibana.keystore"
if [ "$VERBOSE" = "yes" ]; then
    ls -lh /etc/kibana/kibana.keystore
fi
step_done "Initialized Kibana Keystore"

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
# Generate SSL Certificates (if SSL enabled)
# ----------------------------------------------------------------------------
if [ "${ENABLE_BACKEND_SSL:-true}" = "true" ]; then
    step_start "Generating SSL Certificates"
    
    msg_verbose "  → Running elasticsearch-certutil to generate self-signed certificates..."
    
    # Generate self-signed certificates (CA + instance certs)
    if [ "$VERBOSE" = "yes" ]; then
        /usr/share/elasticsearch/bin/elasticsearch-certutil cert \
            --self-signed --pem --out /tmp/certs.zip
    else
        /usr/share/elasticsearch/bin/elasticsearch-certutil cert \
            --self-signed --pem --out /tmp/certs.zip >/dev/null 2>&1
    fi
    
    # Verify cert file was created
    if [ ! -f /tmp/certs.zip ]; then
        msg_error "Failed to generate certificates"
        exit 1
    fi
    msg_verbose "  ✓ Certificate zip created: /tmp/certs.zip"
    
    # Extract certificates
    msg_verbose "  → Extracting certificates..."
    if [ "$VERBOSE" = "yes" ]; then
        unzip -q /tmp/certs.zip -d /tmp/certs
    else
        unzip -q /tmp/certs.zip -d /tmp/certs 2>/dev/null
    fi
    
    # Verify extraction
    if [ ! -d /tmp/certs/instance ]; then
        msg_error "Failed to extract certificates"
        msg_verbose "Certificate directory contents:"
        msg_verbose "$(ls -la /tmp/certs/ 2>&1)"
        exit 1
    fi
    msg_verbose "  ✓ Certificates extracted to /tmp/certs/instance/"
    msg_verbose "  → Certificate structure:"
    if [ "$VERBOSE" = "yes" ]; then
        find /tmp/certs -type f
    fi
    
    msg_verbose "  → Creating certificate directories..."
    mkdir -p /etc/elasticsearch/certs

    # Convert PEM to PKCS12 for Elasticsearch (no password)
    msg_verbose "  → Converting certificates to PKCS12 format..."
    if [ "$VERBOSE" = "yes" ]; then
        openssl pkcs12 -export \
            -in /tmp/certs/instance/instance.crt \
            -inkey /tmp/certs/instance/instance.key \
            -out /etc/elasticsearch/certs/http.p12 \
            -name "http" -passout pass:
    else
        openssl pkcs12 -export \
            -in /tmp/certs/instance/instance.crt \
            -inkey /tmp/certs/instance/instance.key \
            -out /etc/elasticsearch/certs/http.p12 \
            -name "http" -passout pass: 2>/dev/null
    fi
    
    msg_verbose "  → Copying http.p12 to transport.p12..."
    cp /etc/elasticsearch/certs/http.p12 \
        /etc/elasticsearch/certs/transport.p12

    msg_verbose "  → Setting Elasticsearch certificate permissions..."
    chown -R elasticsearch:elasticsearch /etc/elasticsearch/certs
    chmod 660 /etc/elasticsearch/certs/*.p12

    # Copy CA cert for Kibana and Logstash
    msg_verbose "  → Copying CA certificates to Kibana and Logstash..."
    mkdir -p /etc/kibana/certs /etc/logstash/certs
    
    # With --self-signed, CA cert location varies by Elasticsearch version
    # Try multiple possible locations
    CA_FOUND=false
    if [ -f /tmp/certs/ca/ca.crt ]; then
        msg_verbose "  ✓ Found CA at /tmp/certs/ca/ca.crt"
        cp /tmp/certs/ca/ca.crt /etc/kibana/certs/
        cp /tmp/certs/ca/ca.crt /etc/logstash/certs/
        CA_FOUND=true
    elif [ -f /tmp/certs/instance/ca.crt ]; then
        msg_verbose "  ✓ Found CA at /tmp/certs/instance/ca.crt"
        cp /tmp/certs/instance/ca.crt /etc/kibana/certs/
        cp /tmp/certs/instance/ca.crt /etc/logstash/certs/
        CA_FOUND=true
    else
        # Self-signed cert without separate CA - use instance cert as CA
        msg_verbose "  ⚠ No separate CA certificate found, using instance cert as CA"
        if [ -f /tmp/certs/instance/instance.crt ]; then
            cp /tmp/certs/instance/instance.crt /etc/kibana/certs/ca.crt
            cp /tmp/certs/instance/instance.crt /etc/logstash/certs/ca.crt
            CA_FOUND=true
        fi
    fi
    
    if [ "$CA_FOUND" = false ]; then
        msg_error "No certificate files found for CA"
        msg_verbose "  Available files:"
        msg_verbose "$(find /tmp/certs -type f 2>&1)"
        exit 1
    fi
    
    if [ "${ENABLE_FRONTEND_SSL:-true}" = "true" ]; then
        msg_verbose "  → Copying instance certificates to Kibana (SSL enabled)..."
        cp /tmp/certs/instance/instance.crt /etc/kibana/certs/
        cp /tmp/certs/instance/instance.key /etc/kibana/certs/
        chmod 640 /etc/kibana/certs/*
    else
        msg_verbose "  → Configuring Kibana certificates (SSL disabled)..."
        chmod 640 /etc/kibana/certs/ca.crt
    fi

    msg_verbose "  → Setting certificate ownership..."
    chown -R kibana:kibana /etc/kibana/certs
    chown -R logstash:logstash /etc/logstash/certs
    chmod 640 /etc/logstash/certs/ca.crt

    rm -rf /tmp/certs /tmp/certs.zip
    step_done "Generated SSL Certificates"
else
    step_start "Disabling SSL"
    msg_verbose "  → Updating Elasticsearch configuration to disable SSL..."
    # Update Elasticsearch config to disable SSL
    sed -i 's/^xpack.security.enabled: true/xpack.security.enabled: false/' \
        /etc/elasticsearch/elasticsearch.yml
    sed -i 's/^xpack.security.http.ssl.enabled: true/#&/' /etc/elasticsearch/elasticsearch.yml
    sed -i 's/^xpack.security.http.ssl.keystore.path:/#&/' /etc/elasticsearch/elasticsearch.yml
    sed -i 's/^xpack.security.transport.ssl.enabled: true/#&/' /etc/elasticsearch/elasticsearch.yml
    sed -i 's/^xpack.security.transport.ssl.keystore.path:/#&/' /etc/elasticsearch/elasticsearch.yml
    sed -i 's/^xpack.security.transport.ssl.truststore.path:/#&/' /etc/elasticsearch/elasticsearch.yml
    sed -i 's/^xpack.security.transport.ssl.verification_mode:/#&/' /etc/elasticsearch/elasticsearch.yml
    step_done "Disabled SSL"
fi

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
# Set Elasticsearch URL
# ----------------------------------------------------------------------------
if [ "${ENABLE_BACKEND_SSL:-true}" = "true" ]; then
    ES_URL="https://localhost:9200"
    CURL_OPTS="-k"
else
    ES_URL="http://localhost:9200"
    CURL_OPTS=""
fi

# ----------------------------------------------------------------------------
# Generate Elastic Password
# ----------------------------------------------------------------------------
if [ "${ENABLE_BACKEND_SSL:-true}" = "true" ]; then
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
else
    ELASTIC_PASSWORD="disabled"
fi

# ----------------------------------------------------------------------------
# Create Kibana Credentials
# ----------------------------------------------------------------------------
if [ "${ENABLE_BACKEND_SSL:-true}" = "true" ]; then
    step_start "Creating Kibana Service Token"
    msg_verbose "  → Attempting to create Kibana service token via Elasticsearch API..."
    msg_verbose "  → Endpoint: $ES_URL/_security/service/elastic/kibana/credential/token/kibana_token"
    KIBANA_TOKEN=$(curl $CURL_OPTS -s -X POST \
        "$ES_URL/_security/service/elastic/kibana/credential/token/kibana_token" \
        -u "elastic:$ELASTIC_PASSWORD" \
        -H "Content-Type: application/json" \
        | grep -o '"value":"[^"]*' | cut -d'"' -f4)

    # If service token fails, create API key
    if [ -z "$KIBANA_TOKEN" ]; then
        msg_verbose "  ⚠ Service token creation failed, falling back to API key..."
        KIBANA_ROLE='{"name":"kibana_api_key","role_descriptors":{"kibana_system":{"cluster":["monitor","manage_index_templates","manage_ingest_pipelines","manage_ilm"],"indices":[{"names":["*"],"privileges":["all"]}]}}}'
        msg_verbose "  → Creating Kibana API key with role: kibana_system"
        KIBANA_KEY_RESPONSE=$(curl $CURL_OPTS -s -X POST \
            "$ES_URL/_security/api_key" \
            -u "elastic:$ELASTIC_PASSWORD" \
            -H "Content-Type: application/json" \
            -d "$KIBANA_ROLE")
        KIBANA_API_KEY=$(echo "$KIBANA_KEY_RESPONSE" | grep -o '"encoded":"[^"]*' | cut -d'"' -f4)
        msg_verbose "  ✓ Kibana API key created (length: ${#KIBANA_API_KEY} chars)"
    else
        msg_verbose "  ✓ Kibana service token created (length: ${#KIBANA_TOKEN} chars)"
    fi
    step_done "Created Kibana Credentials"

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
    msg_verbose "  ✓ Logstash API key created (length: ${#LOGSTASH_API_KEY} chars)"
    if [ "$VERBOSE" = "yes" ] && [ -n "$LOGSTASH_API_KEY" ]; then
        msg_verbose "  ✓ API key successfully extracted from response"
    fi
    step_done "Created Logstash API Key"

    # ----------------------------------------------------------------------------
    # Configure Kibana Keystore
    # ----------------------------------------------------------------------------
    step_start "Configuring Kibana Keystore"
    export KBN_PATH_CONF=/etc/kibana
    if [ -n "$KIBANA_TOKEN" ]; then
        msg_verbose "  → Adding Kibana service token to keystore (elasticsearch.serviceAccountToken)..."
        if [ "$VERBOSE" = "yes" ]; then
            echo "$KIBANA_TOKEN" | /usr/share/kibana/bin/kibana-keystore add \
                elasticsearch.serviceAccountToken --stdin --force
        else
            echo "$KIBANA_TOKEN" | /usr/share/kibana/bin/kibana-keystore add \
                elasticsearch.serviceAccountToken --stdin --force >/dev/null 2>&1
        fi
        msg_verbose "  ✓ Service token added to keystore"
    else
        msg_verbose "  → Adding Kibana API key to keystore (elasticsearch.apiKey)..."
        if [ "$VERBOSE" = "yes" ]; then
            echo "$KIBANA_API_KEY" | /usr/share/kibana/bin/kibana-keystore add \
                elasticsearch.apiKey --stdin --force
        else
            echo "$KIBANA_API_KEY" | /usr/share/kibana/bin/kibana-keystore add \
                elasticsearch.apiKey --stdin --force >/dev/null 2>&1
        fi
        msg_verbose "  ✓ API key added to keystore"
    fi
    msg_verbose "  → Setting keystore ownership and permissions..."
    chown kibana:root /etc/kibana/kibana.keystore
    chmod 0600 /etc/kibana/kibana.keystore
    msg_verbose "  ✓ Keystore configured with secure permissions"
    if [ "$VERBOSE" = "yes" ]; then
        msg_verbose "  → Listing keystore keys:"
        /usr/share/kibana/bin/kibana-keystore list
    fi
    step_done "Configured Kibana Keystore"

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
fi

# ----------------------------------------------------------------------------
# Configure Logstash Output
# ----------------------------------------------------------------------------
step_start "Configuring Logstash Output"
if [ "${ENABLE_BACKEND_SSL:-true}" = "true" ]; then
    cat > /etc/logstash/conf.d/30-output.conf << 'EOF'

# Logstash output configuration
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
else
    cat > /etc/logstash/conf.d/30-output.conf << 'EOF'

# Logstash output configuration (no SSL)
output {
	elasticsearch {
		hosts => ["http://[::1]:9200"]
		index => "%{[@metadata][beat]}-%{[@metadata][version]}-%{+YYYY.MM.dd}"
	}
}
EOF
fi
step_done "Configured Logstash Output"

# ----------------------------------------------------------------------------
# Configure Kibana Connection
# ----------------------------------------------------------------------------
step_start "Configuring Kibana Connection"
if [ "${ENABLE_BACKEND_SSL:-true}" = "true" ]; then
    if [ "${ENABLE_FRONTEND_SSL:-true}" = "true" ]; then
        # Full HTTPS
        msg_verbose "  → Configuring Kibana with full HTTPS (frontend + backend)..."
        msg_verbose "  → Frontend SSL: Enabled (server.ssl.enabled: true)"
        msg_verbose "  → Backend connection: https://[::1]:9200"
        cat >> /etc/kibana/kibana.yml << 'EOF'

# HTTPS configuration
server.ssl.enabled: true
server.ssl.certificate: /etc/kibana/certs/instance.crt
server.ssl.key: /etc/kibana/certs/instance.key
elasticsearch.hosts: ["https://[::1]:9200"]
elasticsearch.ssl.certificateAuthorities: ["/etc/kibana/certs/ca.crt"]
EOF
        msg_verbose "  ✓ Full HTTPS configuration written"
    else
        # Backend HTTPS only
        msg_verbose "  → Configuring Kibana with backend HTTPS only..."
        msg_verbose "  → Frontend SSL: Disabled (HTTP on port 5601)"
        msg_verbose "  → Backend connection: https://[::1]:9200"
        cat >> /etc/kibana/kibana.yml << 'EOF'

# Backend HTTPS only
elasticsearch.hosts: ["https://[::1]:9200"]
elasticsearch.ssl.certificateAuthorities: ["/etc/kibana/certs/ca.crt"]
EOF
        msg_verbose "  ✓ Backend HTTPS configuration written"
    fi
else
    # No HTTPS
    msg_verbose "  → Configuring Kibana without SSL (HTTP only)..."
    msg_verbose "  → Frontend SSL: Disabled"
    msg_verbose "  → Backend connection: http://[::1]:9200"
    cat >> /etc/kibana/kibana.yml << 'EOF'

# No SSL
elasticsearch.hosts: ["http://[::1]:9200"]
EOF
    msg_verbose "  ✓ No-SSL configuration written"
fi
step_done "Configured Kibana Connection"

# ----------------------------------------------------------------------------
# Save Credentials
# ----------------------------------------------------------------------------
step_start "Saving Credentials"
msg_verbose "  → Writing credentials to /root/elk-credentials.txt..."
msg_verbose "  → Kibana URL: https://$(hostname -I | awk '{print $1}'):5601"
msg_verbose "  → Username: elastic"
msg_verbose "  → Password length: ${#ELASTIC_PASSWORD} characters"
cat > /root/elk-credentials.txt << EOF
ELK Stack Credentials
=====================
Kibana URL: https://$(hostname -I | awk '{print $1}'):5601
Username: elastic
Password: $ELASTIC_PASSWORD

Security Notes:
- SSL/TLS enabled for all components
- API keys stored in keystores
- Certificate files in /etc/*/certs/

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
msg_ok "Completed Successfully!\n"
msg_info "Installation log saved to: $LOG_FILE (inside container)"
msg_info "View credentials: cat /root/elk-credentials.txt"
msg_info "Access Kibana at port 5601 (HTTPS if you enabled SSL)"

# Write final log message
echo "" | tee -a "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - \
ELK Stack installation completed successfully" \
    | tee -a "$LOG_FILE"
echo "Installation log saved to: $LOG_FILE (inside container)" \
    | tee -a "$LOG_FILE"

# Clean up temporary configuration files
rm -rf /tmp/elk-config
