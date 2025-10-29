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
# 1. Standalone mode (build.sh): Self-contained with built-in
#    logging
# 2. Proxmox community script (out/install.sh): Uses framework's
#    msg_* functions
#
# The shim pattern allows the same installation logic to work
# in both contexts.

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

# Define $STD based on VERB/var_verbose (Proxmox framework variable)
# VERB is set by framework: "yes" = verbose, "no" = quiet
if [ "${VERB}" = "yes" ] || [ "${var_verbose}" = "yes" ]; then
    STD=""  # Verbose mode: show all output
else
    STD=" &>/dev/null"  # Quiet mode: suppress output
fi

echo
echo "${TAB3}━━━ ELK Stack Configuration ━━━"
echo
echo "${TAB3}SSL/TLS Configuration:"
echo "${TAB3}[1] Full HTTPS (Elasticsearch + Kibana) [Recommended]"
echo "${TAB3}[2] Backend only (Elasticsearch HTTPS, Kibana HTTP)"
echo "${TAB3}[3] No SSL (HTTP only - testing/dev)"
read -rp "${TAB3}Enter your choice (default: 1): " SSL_CHOICE
SSL_CHOICE=${SSL_CHOICE:-1}

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

echo
read -rp "${TAB3}Customize JVM heap sizes? (default: Elasticsearch 2GB, Logstash 1GB) [y/N]: " CUSTOMIZE_MEMORY
if [[ ${CUSTOMIZE_MEMORY,,} =~ ^(y|yes)$ ]]; then
  echo "${TAB3}Memory Configuration:"
  read -rp "${TAB3}Elasticsearch heap size in GB (default: 2): " ES_HEAP_GB
  ES_HEAP_GB=${ES_HEAP_GB:-2}
  read -rp "${TAB3}Logstash heap size in GB (default: 1): " LS_HEAP_GB
  LS_HEAP_GB=${LS_HEAP_GB:-1}
else
  ES_HEAP_GB=2
  LS_HEAP_GB=1
fi

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

# Handle configuration file deployment
# In standalone mode: Reads from /tmp/elk-config (pushed by build.sh)
# In Proxmox mode: Embeds files inline (defined in Makefile)
if ! command -v handle_config &> /dev/null; then
    handle_config() {
        local source="/tmp/elk-config/$1"
        local dest="$2"
        local mode="${3:-overwrite}"  # append or overwrite
        
        if [ "$mode" = "append" ]; then
            cat "$source" >> "$dest" 2>> "$LOG_FILE"
        else
            cat "$source" > "$dest" 2>> "$LOG_FILE"
        fi
    }
fi

# ============================================================================
# INSTALLATION STEPS
# ============================================================================

# ----------------------------------------------------------------------------
# Update repositories
# ----------------------------------------------------------------------------
step_start "Update repositories"
if ! $STD apt-get update; then
    echo "ERROR: Failed to update repositories" | tee -a "$LOG_FILE"
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
    echo "ERROR: Failed to install dependencies" | tee -a "$LOG_FILE"
    exit 1
fi
step_done "Installed Dependencies"

# ----------------------------------------------------------------------------
# Add Elastic Repository
# ----------------------------------------------------------------------------
step_start "Adding Elastic Repository"
# Download and install Elastic GPG key
$STD wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | \
    gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg

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
# Log download information
echo "$(date '+%Y-%m-%d %H:%M:%S') - Downloading ~2GB, \
takes 5-15 minutes depending on network speed" | tee -a "$LOG_FILE"
# Install all three ELK components
if ! $STD apt-get install -y elasticsearch logstash kibana; then
    echo "ERROR: Failed to install ELK Stack packages" | tee -a "$LOG_FILE"
    exit 1
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
handle_config "elasticsearch.yml" \
    "/etc/elasticsearch/elasticsearch.yml" "append"

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
handle_config "00-input.conf" "/etc/logstash/conf.d/00-input.conf"
handle_config "30-output.conf" "/etc/logstash/conf.d/30-output.conf"

# Configure heap size based on user input  
cat > /etc/logstash/jvm.options.d/heap.options << EOF

# JVM heap settings for Logstash
-Xms${LS_HEAP_GB:-1}g
-Xmx${LS_HEAP_GB:-1}g
EOF
step_done "Deployed Logstash Configuration"

# ----------------------------------------------------------------------------
# Deploy Kibana Configuration
# ----------------------------------------------------------------------------
step_start "Deploying Kibana Configuration"
handle_config "kibana.yml" "/etc/kibana/kibana.yml" "append"
step_done "Deployed Kibana Configuration"

# ----------------------------------------------------------------------------
# Generate Keystore Passwords
# ----------------------------------------------------------------------------
step_start "Generating Keystore Passwords"
# Generate secure random password for Logstash keystore (required v8+)
LOGSTASH_KEYSTORE_PASS=$(openssl rand -base64 32)

# Store in /etc/default/logstash for systemd service
echo "LOGSTASH_KEYSTORE_PASS=\"${LOGSTASH_KEYSTORE_PASS}\"" \
    > /etc/default/logstash
chown root:root /etc/default/logstash
chmod 0600 /etc/default/logstash

# Add to root's environment for interactive sessions
if ! grep -q "LOGSTASH_KEYSTORE_PASS" /root/.bashrc; then
    echo "" >> /root/.bashrc
    echo "# Logstash keystore password" >> /root/.bashrc
    echo "export LOGSTASH_KEYSTORE_PASS=\"\
${LOGSTASH_KEYSTORE_PASS}\"" >> /root/.bashrc
fi

# Export for current session
export LOGSTASH_KEYSTORE_PASS

step_done "Generated Keystore Passwords"

# ----------------------------------------------------------------------------
# Initialize Keystores
# ----------------------------------------------------------------------------
step_start "Initializing Kibana Keystore"
# Create Kibana keystore for secure credential storage
# Kibana keystore uses file permissions (0600) for security
rm -f /etc/kibana/kibana.keystore
export KBN_PATH_CONF=/etc/kibana
/usr/share/kibana/bin/kibana-keystore create
chown kibana:root /etc/kibana/kibana.keystore
chmod 0600 /etc/kibana/kibana.keystore
step_done "Initialized Kibana Keystore"

step_start "Initializing Logstash Keystore"
# Create Logstash keystore with password (required in v8+)
# Password passed via LOGSTASH_KEYSTORE_PASS environment variable
rm -f /etc/logstash/logstash.keystore
/usr/share/logstash/bin/logstash-keystore \
    --path.settings /etc/logstash create 
chown logstash:root /etc/logstash/logstash.keystore
chmod 0600 /etc/logstash/logstash.keystore
step_done "Initialized Logstash Keystore"

# ----------------------------------------------------------------------------
# Generate SSL Certificates (if SSL enabled)
# ----------------------------------------------------------------------------
if [ "${ENABLE_BACKEND_SSL:-true}" = "true" ]; then
    step_start "Generating SSL Certificates"
    $STD /usr/share/elasticsearch/bin/elasticsearch-certutil cert \
        --silent --pem --out /tmp/certs.zip
    $STD unzip -q /tmp/certs.zip -d /tmp/certs
    mkdir -p /etc/elasticsearch/certs

    # Convert PEM to PKCS12 for Elasticsearch
    $STD openssl pkcs12 -export \
        -in /tmp/certs/instance/instance.crt \
        -inkey /tmp/certs/instance/instance.key \
        -out /etc/elasticsearch/certs/http.p12 \
        -name "http" -passout pass:
    cp /etc/elasticsearch/certs/http.p12 \
        /etc/elasticsearch/certs/transport.p12

    chown -R elasticsearch:elasticsearch /etc/elasticsearch/certs
    chmod 660 /etc/elasticsearch/certs/*.p12

    # Copy CA cert for Kibana and Logstash
    mkdir -p /etc/kibana/certs /etc/logstash/certs
    cp /tmp/certs/ca/ca.crt /etc/kibana/certs/
    cp /tmp/certs/ca/ca.crt /etc/logstash/certs/
    
    if [ "${ENABLE_FRONTEND_SSL:-true}" = "true" ]; then
        cp /tmp/certs/instance/instance.crt /etc/kibana/certs/
        cp /tmp/certs/instance/instance.key /etc/kibana/certs/
        chmod 640 /etc/kibana/certs/*
    else
        chmod 640 /etc/kibana/certs/ca.crt
    fi

    chown -R kibana:kibana /etc/kibana/certs
    chown -R logstash:logstash /etc/logstash/certs
    chmod 640 /etc/logstash/certs/ca.crt

    rm -rf /tmp/certs /tmp/certs.zip
    step_done "Generated SSL Certificates"
else
    step_start "Disabling SSL"
    # Update Elasticsearch config to disable SSL
    $STD sed -i 's/xpack.security.http.ssl.enabled: true/xpack.security.enabled: false/' \
        /etc/elasticsearch/elasticsearch.yml
    $STD sed -i '/xpack.security.http.ssl.keystore.path/d' /etc/elasticsearch/elasticsearch.yml
    $STD sed -i '/xpack.security.transport.ssl/d' /etc/elasticsearch/elasticsearch.yml
    step_done "Disabled SSL"
fi

# ----------------------------------------------------------------------------
# Start Elasticsearch (needed for user/key creation)
# ----------------------------------------------------------------------------
step_start "Starting Elasticsearch"
systemctl enable elasticsearch
$STD systemctl start elasticsearch
sleep 30
step_done "Started Elasticsearch"

# ----------------------------------------------------------------------------
# Configure Security
# ----------------------------------------------------------------------------
step_start "Configuring Security"

# Determine Elasticsearch URL based on SSL configuration
if [ "${ENABLE_BACKEND_SSL:-true}" = "true" ]; then
    ES_URL="https://localhost:9200"
    CURL_OPTS="-k"
else
    ES_URL="http://localhost:9200"
    CURL_OPTS=""
fi

# Generate and set elastic password (only if SSL enabled)
if [ "${ENABLE_BACKEND_SSL:-true}" = "true" ]; then
    ELASTIC_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)
    echo "$ELASTIC_PASSWORD" | $STD /usr/share/elasticsearch/bin/elasticsearch-reset-password \
        -u elastic -b -s -i
else
    ELASTIC_PASSWORD="disabled"
fi

# Create Kibana service token (only if auth enabled)
if [ "${ENABLE_BACKEND_SSL:-true}" = "true" ]; then
    KIBANA_TOKEN=$(curl $CURL_OPTS -s -X POST \
        "$ES_URL/_security/service/elastic/kibana/credential/token/kibana_token" \
        -u "elastic:$ELASTIC_PASSWORD" \
        -H "Content-Type: application/json" \
        | grep -o '"value":"[^"]*' | cut -d'"' -f4)

    # If service token fails, create API key
    if [ -z "$KIBANA_TOKEN" ]; then
        KIBANA_ROLE='{"name":"kibana_api_key","role_descriptors":{"kibana_system":{"cluster":["monitor","manage_index_templates","manage_ingest_pipelines","manage_ilm"],"indices":[{"names":["*"],"privileges":["all"]}]}}}'
        KIBANA_KEY_RESPONSE=$(curl $CURL_OPTS -s -X POST \
            "$ES_URL/_security/api_key" \
            -u "elastic:$ELASTIC_PASSWORD" \
            -H "Content-Type: application/json" \
            -d "$KIBANA_ROLE")
        KIBANA_API_KEY=$(echo "$KIBANA_KEY_RESPONSE" | grep -o '"encoded":"[^"]*' | cut -d'"' -f4)
    fi

    # Create Logstash API key
    LOGSTASH_ROLE='{"name":"logstash_writer","role_descriptors":{"logstash_writer":{"cluster":["monitor","manage_index_templates","manage_ilm"],"indices":[{"names":["logs-*","logstash-*","ecs-*"],"privileges":["write","create","create_index","manage","manage_ilm"]}]}}}'
    LOGSTASH_KEY_RESPONSE=$(curl $CURL_OPTS -s -X POST \
        "$ES_URL/_security/api_key" \
        -u "elastic:$ELASTIC_PASSWORD" \
        -H "Content-Type: application/json" \
        -d "$LOGSTASH_ROLE")
    LOGSTASH_API_KEY=$(echo "$LOGSTASH_KEY_RESPONSE" | grep -o '"encoded":"[^"]*' | cut -d'"' -f4)

    # Configure Kibana keystore
    if [ -n "$KIBANA_TOKEN" ]; then
        export KBN_PATH_CONF=/etc/kibana
        echo "$KIBANA_TOKEN" | /usr/share/kibana/bin/kibana-keystore add \
            elasticsearch.serviceAccountToken --stdin --force
    else
        export KBN_PATH_CONF=/etc/kibana
        echo "$KIBANA_API_KEY" | /usr/share/kibana/bin/kibana-keystore add \
            elasticsearch.apiKey --stdin --force
    fi
    chown kibana:root /etc/kibana/kibana.keystore
    chmod 0600 /etc/kibana/kibana.keystore

    # Configure Logstash keystore
    echo "$LOGSTASH_API_KEY" | /usr/share/logstash/bin/logstash-keystore \
        --path.settings /etc/logstash \
        add ELASTICSEARCH_API_KEY --stdin --force
    chown logstash:root /etc/logstash/logstash.keystore
    chmod 0600 /etc/logstash/logstash.keystore
fi

# Update Logstash output configuration
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

# Configure Kibana HTTPS based on settings
if [ "${ENABLE_BACKEND_SSL:-true}" = "true" ]; then
    if [ "${ENABLE_FRONTEND_SSL:-true}" = "true" ]; then
        # Full HTTPS
        cat >> /etc/kibana/kibana.yml << 'EOF'

# HTTPS configuration
server.ssl.enabled: true
server.ssl.certificate: /etc/kibana/certs/instance.crt
server.ssl.key: /etc/kibana/certs/instance.key
elasticsearch.hosts: ["https://[::1]:9200"]
elasticsearch.ssl.certificateAuthorities: ["/etc/kibana/certs/ca.crt"]
EOF
    else
        # Backend HTTPS only
        cat >> /etc/kibana/kibana.yml << 'EOF'

# Backend HTTPS only
elasticsearch.hosts: ["https://[::1]:9200"]
elasticsearch.ssl.certificateAuthorities: ["/etc/kibana/certs/ca.crt"]
EOF
    fi
else
    # No HTTPS
    cat >> /etc/kibana/kibana.yml << 'EOF'

# No SSL
elasticsearch.hosts: ["http://[::1]:9200"]
EOF
fi

# Save credentials to file
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
- Rotate API keys: /root/elk-rotate-api-keys.sh
- Reset password: /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic
EOF
chmod 600 /root/elk-credentials.txt

step_done "Configured Security"

# ----------------------------------------------------------------------------
# Enable and Start Services
# ----------------------------------------------------------------------------
step_start "Starting Services"
systemctl enable logstash kibana
$STD systemctl start logstash kibana
step_done "Started Services"

# ============================================================================
# INSTALLATION COMPLETE
# ============================================================================
msg_ok "Completed Successfully!\n"
msg_info "Installation log saved to: $LOG_FILE (inside container)"
msg_info "View credentials: cat /root/elk-credentials.txt"
msg_info "Access Kibana: http${ENABLE_BACKEND_SSL:-true ? 's' : ''}://$(hostname -I | awk '{print $1}'):5601"
msg_info "Manage API keys: /root/elk-rotate-api-keys.sh"

# Write final log message
echo "" | tee -a "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - \
ELK Stack installation completed successfully" \
    | tee -a "$LOG_FILE"
echo "Installation log saved to: $LOG_FILE (inside container)" \
    | tee -a "$LOG_FILE"

# Clean up temporary configuration files
rm -rf /tmp/elk-config
