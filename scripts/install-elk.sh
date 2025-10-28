#!/bin/bash
# Copyright (c) 2025 Alex Goodkind
# Author: Alex Goodkind (agoodkind)
# License: Apache-2.0
#
# ELK Stack Installation Script - Single Source of Truth
#
# This script installs and configures the full ELK Stack (Elasticsearch, Logstash, Kibana)
# on Ubuntu 24.04. It works in two modes:
#
# 1. Standalone mode (build.sh): Self-contained with built-in logging
# 2. Proxmox community script (out/install.sh): Uses framework's msg_* functions
#
# The shim pattern allows the same installation logic to work in both contexts.

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================

# Step counter (auto-increments with each step)
STEP=0

# ============================================================================
# LOGGING SETUP
# ============================================================================

# Initialize logging (if not already set by caller)
# Proxmox framework will define LOG_FILE, standalone mode uses default
LOG_FILE="${LOG_FILE:-/var/log/elk-install.log}"
if [ ! -f "$LOG_FILE" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting ELK Stack installation" | tee "$LOG_FILE"
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
# Install System Dependencies
# ----------------------------------------------------------------------------
step_start "Installing Dependencies"
# Required: wget (download GPG key), gnupg (process GPG), apt-transport-https & ca-certificates (HTTPS repos)
#           openjdk-11 (Java for ELK), curl (API calls), unzip & openssl (SSL cert management)
if ! apt-get install -y \
    wget gnupg apt-transport-https ca-certificates \
    openjdk-11-jre-headless curl unzip openssl; then
    echo "ERROR: Failed to install dependencies" | tee -a "$LOG_FILE"
    exit 1
fi
step_done "Installing Dependencies"

# ----------------------------------------------------------------------------
# Add Elastic Repository
# ----------------------------------------------------------------------------
step_start "Adding Elastic Repository"
# Download and install Elastic GPG key
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | \
    gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg

# Add Elastic 8.x repository
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" \
    > /etc/apt/sources.list.d/elastic-8.x.list
step_done "Adding Elastic Repository"

# ----------------------------------------------------------------------------
# Update Package Lists
# ----------------------------------------------------------------------------
step_start "Updating Package Lists"
# Update package list to include Elastic repository
apt-get update
step_done "Updating Package Lists"

# ----------------------------------------------------------------------------
# Install ELK Stack Packages
# ----------------------------------------------------------------------------
step_start "Installing ELK Stack (Elasticsearch, Logstash, Kibana)"
# Log download information
echo "$(date '+%Y-%m-%d %H:%M:%S') - Downloading ~2GB of packages, this will take 5-15 minutes depending on network speed" | tee -a "$LOG_FILE"
# Install all three ELK components
if ! apt-get install -y elasticsearch logstash kibana; then
    echo "ERROR: Failed to install ELK Stack packages" | tee -a "$LOG_FILE"
    exit 1
fi
step_done "Installing ELK Stack (Elasticsearch, Logstash, Kibana)"

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
handle_config "elasticsearch.yml" "/etc/elasticsearch/elasticsearch.yml" "append"
handle_config "elasticsearch.options" "/etc/elasticsearch/jvm.options.d/heap.options"
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
handle_config "logstash.options" "/etc/logstash/jvm.options.d/heap.options"
step_done "Deployed Logstash Configuration"

# ----------------------------------------------------------------------------
# Deploy Kibana Configuration
# ----------------------------------------------------------------------------
step_start "Deploying Kibana Configuration"
handle_config "kibana.yml" "/etc/kibana/kibana.yml" "append"
step_done "Deployed Kibana Configuration"

# ----------------------------------------------------------------------------
# Initialize Keystores
# ----------------------------------------------------------------------------
step_start "Initializing Keystores"
# Create Kibana keystore (for secure credential storage)
# --force flag overwrites existing keystore without prompting
# echo | provides empty input to avoid prompts
echo | /usr/share/kibana/bin/kibana-keystore create --force
chown kibana:kibana /etc/kibana/kibana.keystore
chmod 660 /etc/kibana/kibana.keystore

# Create Logstash keystore
echo | /usr/share/logstash/bin/logstash-keystore create
chown logstash:logstash /etc/logstash/logstash.keystore
chmod 660 /etc/logstash/logstash.keystore
step_done "Initialized Keystores"

# ----------------------------------------------------------------------------
# Enable Services
# ----------------------------------------------------------------------------
step_start "Enabling Services"
# Enable services to start on boot (services are not started yet)
systemctl enable elasticsearch logstash kibana
step_done "Enabled Services"

# ============================================================================
# INSTALLATION COMPLETE
# ============================================================================
msg_ok "Completed Successfully!\n"

# Write final log message
echo "" | tee -a "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - ELK Stack installation completed successfully" | tee -a "$LOG_FILE"
echo "Installation log saved to: $LOG_FILE" | tee -a "$LOG_FILE"

# Clean up temporary configuration files
rm -rf /tmp/elk-config
