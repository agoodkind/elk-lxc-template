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

# ============================================================================
# LOGGING SETUP
# ============================================================================

# Initialize logging (if not already set by caller)
# Proxmox framework will define LOG_FILE, standalone mode uses default
LOG_FILE="${LOG_FILE:-/tmp/elk-install.log}"
if [ ! -f "$LOG_FILE" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - \
Starting ELK Stack installation" | tee "$LOG_FILE"
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

# Display warning message
if ! command -v msg_warn &> /dev/null; then
    msg_warn() {
        echo "⚠ $1" | tee -a "$LOG_FILE"
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

# Define verbose logging function
msg_verbose() {
    if [ "${VERBOSE}" = "yes" ] || [ "${var_verbose}" = "yes" ]; then
        if [ -n "${LOG_FILE:-}" ]; then
            echo "$@" | tee -a "$LOG_FILE"
        else
            echo "$@"
        fi
    fi
}

# Define debug function to show file contents
msg_debug() {
    if [ "${DEBUG}" = "yes" ] ; then
        local msg="$1"
        local file="$2"
        local output=""
        
        if [ -n "$file" ] && [ -f "$file" ]; then
            # Extract non-comment, non-empty lines
            local file_content=$(grep -v "^#" "$file" | \
                grep -v "^$" | \
                head -20 | \
                sed 's/^/DEBUG      /' || \
                echo "DEBUG      (empty or all comments)")
            output=$(echo -e "DEBUG: $msg\n---\n$file_content")
        elif [ -n "$file" ]; then
            output="DEBUG: $msg (file $file doesn't exist)"
        else
            output="DEBUG: $msg"
        fi

        if [ -n "${LOG_FILE:-}" ]; then
            echo -e "$output" | tee -a "$LOG_FILE"
        else
            echo -e "$output"
        fi
    fi
}

# Define error logging function
msg_error() {
    local error_msg="✗ ERROR: $*"
    if [ -n "${LOG_FILE:-}" ]; then
        echo "$error_msg" | tee -a "$LOG_FILE"
    else
        echo "$error_msg"
    fi
    
    # In verbose mode, show last ~100 lines of Elasticsearch log if available
    if [ "${VERBOSE}" = "yes" ] || [ "${var_verbose}" = "yes" ]; then
        local app_name="${app:-${APPLICATION:-elasticsearch}}"
        local es_log="/var/log/elasticsearch/${app_name}.log"
        if [ -f "$es_log" ]; then
            {
                echo ""
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "Last ~100 lines of Elasticsearch log ($es_log):"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                tail -n 100 "$es_log" 2>/dev/null || echo "  (unable to read log file)"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo ""
            } | if [ -n "${LOG_FILE:-}" ]; then tee -a "$LOG_FILE"; else cat; fi
        fi
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
        echo "  VERBOSE: ${VERBOSE:-<not set>}"
        echo "  DEBUG: ${DEBUG:-<not set>}"
        echo "  APPLICATION: ${APPLICATION:-<not set>}"
        echo "  APP: ${APP:-<not set>}"
        echo "  NSAPP: ${NSAPP:-<not set>}"
        echo "  CTID: ${CTID:-<not set>}"
        echo "  IP: ${IP:-<not set>}"
        echo "  STD: ${STD:-<empty/verbose>}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        msg_debug "Debug Message Test" 
        msg_error "Error Message Test"
        msg_verbose "Verbose Message Test"
        msg_info "Info Message Test"
        msg_ok "OK Message Test"
    else
        STD="silent"  # Quiet mode: use silent function
    fi
fi

if [[ ${CUSTOMIZE_MEMORY,,} =~ ^(y|yes)$ ]]; then
  if [ -z "$ES_HEAP_GB" ]; then
    echo "${TAB3}Memory Configuration:"
    read -rp "${TAB3}Elasticsearch heap size in GB (default: 4): " ES_HEAP_GB </dev/tty
  fi
  ES_HEAP_GB=${ES_HEAP_GB:-4}
  
  if [ -z "$LS_HEAP_GB" ]; then
    read -rp "${TAB3}Logstash heap size in GB (default: 2): " LS_HEAP_GB </dev/tty
  fi
  LS_HEAP_GB=${LS_HEAP_GB:-2}
else
  ES_HEAP_GB=4
  LS_HEAP_GB=2
fi

msg_verbose "Final configuration:"
msg_verbose "  → Security + SSL: Always enabled (Elasticsearch auto-config)"
msg_verbose "  → Elasticsearch Heap: ${ES_HEAP_GB}GB"
msg_verbose "  → Logstash Heap: ${LS_HEAP_GB}GB"
msg_verbose ""

echo

# ============================================================================
# INSTALLATION STEPS
# ============================================================================

# ----------------------------------------------------------------------------
# Update repositories
# ----------------------------------------------------------------------------
step_start "Update repositories"
if ! DEBIAN_FRONTEND=noninteractive apt-get update -qq; then
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
if ! DEBIAN_FRONTEND=noninteractive apt-get install -qq -y \
    wget gnupg apt-transport-https ca-certificates \
    openjdk-11-jre-headless curl unzip openssl \
    htop net-tools vim jq; then
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
if ! DEBIAN_FRONTEND=noninteractive apt-get update -qq; then
    msg_error "Failed to update package lists"
    exit 1
fi
step_done "Updated Package Lists"

# ----------------------------------------------------------------------------
# Install ELK Stack Packages
# ----------------------------------------------------------------------------
step_start "Installing ELK Stack (Elasticsearch, Logstash, Kibana)"
msg_info "  → Downloading packages (~3GB, may take 5-15 minutes)..."
# Install all three ELK components
if [ "${DEBUG}" = "yes" ]; then
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y elasticsearch logstash kibana ; then
        msg_error "Failed to install ELK Stack packages"
        exit 1
    fi
else
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -qq -y elasticsearch logstash kibana > /dev/null 2>&1 ; then
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
# Configure Elasticsearch JVM Heap (only)
# ----------------------------------------------------------------------------
# We don't touch elasticsearch.yml before startup - let auto-config handle everything
# Network settings will be configured after auto-config completes
step_start "Configuring Elasticsearch JVM Heap"
msg_debug "Existing jvm.options.d/heap.options" /etc/elasticsearch/jvm.options.d/heap.options
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
step_start "Configuring Logstash JVM Heap"
msg_verbose "  → Configuring Logstash JVM heap size..."
msg_debug "Existing jvm.options.d/heap.options" /etc/logstash/jvm.options.d/heap.options
# Configure heap size
cat > /etc/logstash/jvm.options.d/heap.options << EOF
# JVM heap settings for Logstash
-Xms${LS_HEAP_GB:-1}g
-Xmx${LS_HEAP_GB:-1}g
EOF

step_done "Deployed Logstash Configuration"

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
# Use NSAPP variable for cluster name (follows Proxmox patterns)
CLUSTER_NAME="${NSAPP:-ELK-Stack}"
cat >> /etc/elasticsearch/elasticsearch.yml << EOF

# Network configuration (added after auto-config)
network.host: ["_local_", "_site_"]

# Cluster identification (uses NSAPP variable)
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
msg_verbose "  → Auto-generating password for elastic user..."

# Use auto-generate mode (-a) with batch mode (-b) to avoid password echo
RESET_OUTPUT=$(/usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -a -b 2>&1)

if [ $? -ne 0 ]; then
    msg_error "Failed to reset elastic user password"
    msg_verbose "  → Output: $RESET_OUTPUT"
    exit 1
fi

# Extract password from output (case-insensitive for "new value")
ELASTIC_PASSWORD=$(echo "$RESET_OUTPUT" | grep -i "new value" | awk '{print $NF}')
msg_debug "Extracted password: $ELASTIC_PASSWORD"
if [ -z "$ELASTIC_PASSWORD" ]; then
    msg_error "Failed to extract password from reset output"
    exit 1
fi
msg_verbose "  ✓ Password generated (length: ${#ELASTIC_PASSWORD} chars)"

# Verify authentication works
msg_verbose "  → Verifying password authentication..."
MAX_AUTH_WAIT=30
AUTH_WAIT=0
while [ $AUTH_WAIT -lt $MAX_AUTH_WAIT ]; do
    
    AUTH_TEST=$(curl $CURL_OPTS -s -u "elastic:$ELASTIC_PASSWORD" \
        -X GET "$ES_URL/_security/_authenticate" 2>&1)
    msg_debug "Auth test response: $AUTH_TEST"

    if echo "$AUTH_TEST" | grep -q '"username":"elastic"'; then
        msg_verbose "  ✓ Password verified successfully"
        break
    fi
    sleep 2
    AUTH_WAIT=$((AUTH_WAIT + 2))
done

if [ $AUTH_WAIT -ge $MAX_AUTH_WAIT ]; then
    msg_error "Password reset completed but authentication verification failed"
    msg_verbose "  → Auth test response: $AUTH_TEST"
    exit 1
fi

msg_verbose "  ✓ Authentication verified"
step_done "Generated Elastic Password"

# ----------------------------------------------------------------------------
# Configure Kibana (consolidated: basic config + enrollment)
# ----------------------------------------------------------------------------
step_start "Configuring Kibana"
msg_debug "Existing kibana.yml" /etc/kibana/kibana.yml

# Configure basic server settings
msg_verbose "  → Configuring Kibana server settings..."
sed -i 's/^server.port:/#&/' /etc/kibana/kibana.yml
sed -i 's/^server.host:/#&/' /etc/kibana/kibana.yml
sed -i 's/^elasticsearch.hosts:/#&/' /etc/kibana/kibana.yml
sed -i 's/^elasticsearch.username:/#&/' /etc/kibana/kibana.yml
sed -i 's/^elasticsearch.password:/#&/' /etc/kibana/kibana.yml

cat >> /etc/kibana/kibana.yml << 'EOF'

# ============================================================================
# Kibana Configuration
# ============================================================================

# Kibana server configuration
server.port: 5601
# Prefer IPv6 and listen on all interfaces
server.host: "::"
EOF

# Generate and apply enrollment token
msg_verbose "  → Creating enrollment token for Kibana..."
ENROLLMENT_TOKEN=$(/usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana)
msg_debug "Enrollment token: $ENROLLMENT_TOKEN"

if [ -z "$ENROLLMENT_TOKEN" ]; then
    msg_error "Failed to generate Kibana enrollment token"
    msg_verbose "  → Check if xpack.security.enrollment.enabled is true"
    msg_verbose "  → Check Elasticsearch logs for auto-configuration errors"
    exit 1
fi
msg_verbose "  ✓ Enrollment token created (length: ${#ENROLLMENT_TOKEN} chars)"

msg_verbose "  → Applying enrollment token (configures backend connection to Elasticsearch)..."
if ! /usr/share/kibana/bin/kibana-setup --enrollment-token "$ENROLLMENT_TOKEN"; then
    msg_error "Failed to apply enrollment token to Kibana"
    exit 1
fi

# Update Elasticsearch connection to use localhost instead of IP
msg_verbose "  → Updating elasticsearch.hosts to use localhost..."
sed -i 's|elasticsearch.hosts:.*|elasticsearch.hosts: [https://localhost:9200]|' /etc/kibana/kibana.yml

msg_verbose "  ✓ Kibana backend configured (HTTPS to Elasticsearch via localhost)"
step_done "Configured Kibana"

# ----------------------------------------------------------------------------
# Create Logstash API Key
# ----------------------------------------------------------------------------
step_start "Creating Logstash API Key"
msg_verbose "  → Defining Logstash writer role permissions for all indices"
LOGSTASH_ROLE=$(cat <<'EOF'
{
  "name": "logstash_writer",
  "role_descriptors": {
    "logstash_writer": {
      "cluster": ["monitor", "manage_index_templates", "manage_ilm"],
      "indices": [{
        "names": ["*"],
        "privileges": [
          "read", "write", "create", "create_index",
          "delete", "manage", "manage_ilm", "auto_configure"
        ]
      }]
    }
  }
}
EOF
)
msg_verbose "  → Creating API key via Elasticsearch API..."
msg_verbose "  → Endpoint: $ES_URL/_security/api_key"

LOGSTASH_KEY_RESPONSE=$(curl $CURL_OPTS -s -X POST \
    "$ES_URL/_security/api_key" \
    -u "elastic:$ELASTIC_PASSWORD" \
    -H "Content-Type: application/json" \
    -d "$LOGSTASH_ROLE")

msg_debug "Logstash key response: $LOGSTASH_KEY_RESPONSE"

# Extract ID and API key from JSON response
LOGSTASH_ID=$(echo "$LOGSTASH_KEY_RESPONSE" | jq -r '.id')
LOGSTASH_KEY=$(echo "$LOGSTASH_KEY_RESPONSE" | jq -r '.api_key')

# Combine as id:api_key format
LOGSTASH_API_KEY="${LOGSTASH_ID}:${LOGSTASH_KEY}"

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

echo "$LOGSTASH_API_KEY" | /usr/share/logstash/bin/logstash-keystore \
    --path.settings /etc/logstash \
    add ELASTICSEARCH_API_KEY --stdin

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
step_start "Configuring Logstash Input"
cat > /etc/logstash/conf.d/10-input.conf << 'EOF'

# Logstash input configuration (HTTP POST)
input {
	http {
		port => 8080
		codec => json
	}
}
EOF
step_done "Configured Logstash Input"

step_start "Configuring Logstash Filter"
cat > /etc/logstash/conf.d/20-filter.conf << 'EOF'

# Logstash filter configuration (pass through verbatim with data_stream fields)
filter {
	mutate {
		add_field => {
			"[data_stream][type]" => "logs"
			"[data_stream][dataset]" => "generic"
			"[data_stream][namespace]" => "default"
		}
	}
}
EOF
step_done "Configured Logstash Filter"

step_start "Configuring Logstash Output"
cat > /etc/logstash/conf.d/30-output.conf << 'EOF'

# Logstash output configuration (HTTPS with API key)
output {
	elasticsearch {
		hosts => ["https://localhost:9200"]
		api_key => "${ELASTICSEARCH_API_KEY}"
	    data_stream => true
		ssl_enabled => true
        ssl_certificate_authorities => ["/etc/logstash/certs/ca.crt"]
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
KIBANA_URL="http://$(hostname -I | awk '{print $1}'):5601"

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

Logstash Ingestion:
- HTTP Endpoint: http://$(hostname -I | awk '{print $1}'):8080
- Send logs via HTTP POST with JSON body
- Example:
  curl -X POST http://$(hostname -I | awk '{print $1}'):8080 \\
    -H "Content-Type: application/json" \\
    -d '{"message":"test","level":"info"}'
- Data Stream: logs-generic-default
- View logs in Kibana > Discover > "Generic Logs" data view

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

# ----------------------------------------------------------------------------
# Create Kibana Data View
# ----------------------------------------------------------------------------
step_start "Creating Kibana Data View"
msg_verbose "  → Waiting for Kibana to be ready..."

MAX_WAIT=90
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    if curl -s -k -u "elastic:$ELASTIC_PASSWORD" "http://localhost:5601/api/status" | grep -q "available"; then
        msg_debug "Kibana status available after ${WAITED}s"
        break
    fi
    sleep 2
    WAITED=$((WAITED + 2))
done

if [ $WAITED -ge $MAX_WAIT ]; then
    msg_warn "Kibana did not become ready in time, skipping data view creation"
else
    msg_verbose "  → Waiting for Kibana to fully initialize..."
    sleep 10
    
    msg_verbose "  → Creating data view for logs-generic-default..."
    
    DATAVIEW_CREATED=false
    for attempt in 1 2 3; do
        DATAVIEW_RESPONSE=$(curl -s -k -u "elastic:$ELASTIC_PASSWORD" \
            -X POST "http://localhost:5601/api/data_views/data_view" \
            -H "kbn-xsrf: true" \
            -H "Content-Type: application/json" \
            -d '{
                "data_view": {
                    "title": "logs-generic-*",
                    "name": "Generic Logs",
                    "timeFieldName": "@timestamp"
                }
            }' 2>&1)
        
        msg_debug "Data view response (attempt $attempt): $DATAVIEW_RESPONSE"
        
        if echo "$DATAVIEW_RESPONSE" | grep -q "data_view"; then
            msg_verbose "  ✓ Data view created successfully"
            DATAVIEW_CREATED=true
            break
        elif echo "$DATAVIEW_RESPONSE" | grep -q "not ready"; then
            msg_debug "Kibana not ready, waiting 5s before retry..."
            sleep 5
        else
            break
        fi
    done
    
    if [ "$DATAVIEW_CREATED" = false ]; then
        msg_warn "Data view creation failed or already exists"
    fi
fi

step_done "Created Kibana Data View"

# ----------------------------------------------------------------------------
# Test Log Ingestion
# ----------------------------------------------------------------------------
step_start "Testing Log Ingestion"
msg_verbose "  → Waiting for Logstash to be ready..."

MAX_LOGSTASH_WAIT=30
LOGSTASH_WAITED=0
while [ $LOGSTASH_WAITED -lt $MAX_LOGSTASH_WAIT ]; do
    if netstat -tln | grep -q ":8080 "; then
        msg_debug "Logstash HTTP input ready after ${LOGSTASH_WAITED}s"
        break
    fi
    sleep 2
    LOGSTASH_WAITED=$((LOGSTASH_WAITED + 2))
done

if [ $LOGSTASH_WAITED -ge $MAX_LOGSTASH_WAIT ]; then
    msg_warn "Logstash HTTP input not ready, skipping ingestion test"
    step_done "Skipped Log Ingestion Test"
else
    msg_verbose "  → Sending test log to Logstash..."
    TEST_MESSAGE="ELK Stack installation test log at $(date '+%Y-%m-%d %H:%M:%S')"

    POST_RESPONSE=$(curl -s -X POST "http://localhost:8080" \
        -H "Content-Type: application/json" \
        -d "$(cat <<EOF
{
    "message": "$TEST_MESSAGE",
    "level": "info",
    "source": "elk-installer"
}
EOF
)" 2>&1)

    msg_debug "POST response: $POST_RESPONSE"

    msg_verbose "  → Waiting for log to be indexed..."
    sleep 10

    msg_verbose "  → Querying Elasticsearch for test log..."
    SEARCH_RESPONSE=$(curl -s -k -u "elastic:$ELASTIC_PASSWORD" \
        -X GET "https://localhost:9200/logs-generic-default/_search" \
        -H "Content-Type: application/json" \
        -d "$(cat <<EOF
{
    "query": {
        "match_phrase": {
            "message": "$TEST_MESSAGE"
        }
    },
    "size": 1
}
EOF
)" 2>&1)

    msg_debug "Search response: $SEARCH_RESPONSE"

    if echo "$SEARCH_RESPONSE" | jq -r '.hits.total.value' | grep -qE '^[1-9][0-9]*$'; then
        msg_verbose "  ✓ Test log successfully ingested and indexed"
    else
        msg_warn "Test log not found in Elasticsearch (may need more time to index)"
        msg_debug "Check Logstash logs: tail -f /var/log/logstash/logstash-plain.log"
    fi

    step_done "Tested Log Ingestion"
fi

# ============================================================================
# INSTALLATION COMPLETE
# ============================================================================
msg_ok "Completed Successfully!"

msg_debug "tail -n 100 /var/log/elasticsearch/elasticsearch.log"
msg_debug "$(tail -n 100 /var/log/elasticsearch/elasticsearch.log)"
msg_debug "--------------------------------"
msg_debug "tail -n 100 /var/log/logstash/logstash-plain.log"
msg_debug "$(tail -n 100 /var/log/logstash/logstash-plain.log)"
msg_debug "--------------------------------"
msg_debug "tail -n 100 /var/log/kibana/kibana.log"
msg_debug "$(tail -n 100 /var/log/kibana/kibana.log)"
msg_debug "--------------------------------"

# Write final log message
echo "" | tee -a "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - \
ELK Stack installation completed successfully" \
    | tee -a "$LOG_FILE"